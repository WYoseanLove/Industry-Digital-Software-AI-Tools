import fs from 'node:fs/promises';
import path from 'node:path';
import { createHash, randomUUID } from 'node:crypto';
import { execFile, spawn } from 'node:child_process';
import { promisify } from 'node:util';
import { fileURLToPath } from 'node:url';

export const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
export const products = {
  NX: { runner: 'NX\\tools\\nxrun.ps1', extension: '.cpp' },
  Office: { runner: 'Office\\tools\\officerun.ps1', extension: '.cs' },
  Catia: { runner: 'Catia\\tools\\catrun.ps1', extension: '.cs' },
  Vismockup: { runner: 'Vismockup\\tools\\vmrun.ps1', extension: '.cs' },
  Tecnomatix: { runner: 'Tecnomatix\\Tecnomatix-AI-Client\\tools\\txai.ps1', extension: '.cs' }
};
const maxOutput = 4 * 1024 * 1024;
const excluded = new Set(['.git', 'node_modules', 'bin', 'obj', '.vs']);
const textExtensions = new Set(['.md', '.ps1', '.cs', '.cpp', '.h', '.hxx', '.json', '.csproj', '.tsv', '.csv', '.txt']);

function inside(root, candidate) {
  const relative = path.relative(root, candidate);
  return relative === '' || (!relative.startsWith(`..${path.sep}`) && relative !== '..' && !path.isAbsolute(relative));
}

export async function resolveSafe(root, relative, allowMissing = false) {
  if (typeof relative !== 'string' || relative.includes('\0') || path.isAbsolute(relative) ||
      relative.split(/[\\/]/).some(part => part === '..' || excluded.has(part.toLowerCase()) || part.includes(':'))) {
    throw new Error('Use a repository-relative path without parent traversal, excluded folders or alternate streams.');
  }
  const candidate = path.resolve(root, relative);
  const realRoot = await fs.realpath(root);
  if (!inside(root, candidate)) throw new Error('Path is outside the allowed directory.');
  let probe = candidate;
  for (;;) {
    try {
      const real = await fs.realpath(probe);
      if (!inside(realRoot, real)) throw new Error('Symlink or junction points outside the allowed directory.');
      break;
    } catch (error) {
      if (!allowMissing || error.code !== 'ENOENT' || probe === root) throw error;
      probe = path.dirname(probe);
    }
  }
  return candidate;
}

export async function executeRunner(root, request, onOutput) {
  const powershell = path.join(process.env.SystemRoot || 'C:\\Windows', 'System32', 'WindowsPowerShell', 'v1.0', 'powershell.exe');
  const adapter = path.join(root, 'tools', 'mcp', 'invoke-runner.ps1');
  const { signal, ...payload } = request;
  const inherited = { ...process.env, MFG_TASK_HINT: request.taskHint, MFG_MCP_REQUEST: JSON.stringify(payload) };
  let bootstrap;
  let bootstrapClosed;
  try {
    const pending = promisify(execFile)(powershell,
      ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', adapter, '-PrintEnvironment'],
      { cwd: root, env: inherited, windowsHide: true, timeout: 10000, maxBuffer: 1024 * 1024, signal });
    bootstrapClosed = new Promise(resolve => pending.child.once('close', resolve));
    bootstrap = await pending;
  } catch (error) {
    if (signal?.aborted) throw new Error('MCP connection closed; environment bootstrap was stopped.');
    throw new Error(`MCP environment bootstrap failed (${error.code ?? 'process error'}): ${error.stderr || 'unable to read Windows process settings'}`);
  } finally {
    await bootstrapClosed;
  }
  let recovered;
  try {
    recovered = JSON.parse(bootstrap.stdout);
  } catch {
    throw new Error('MCP environment bootstrap returned invalid JSON; no runner was started.');
  }
  if (!recovered || typeof recovered.environment !== 'object' || recovered.environment === null ||
      !Object.values(recovered.environment).every(value => typeof value === 'string')) {
    throw new Error('MCP environment bootstrap returned an invalid environment; no runner was started.');
  }
  if (recovered.restoredCount > 0 || recovered.pathChanged || recovered.extensionsChanged) {
    onOutput(`[MCP] Restored ${recovered.restoredCount} missing environment variables and merged Windows PATH/PATHEXT before runner startup (process only).\n`);
  }
  return new Promise((resolve, reject) => {
    const child = spawn(powershell, ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', adapter], {
      cwd: root,
      env: recovered.environment,
      stdio: ['ignore', 'pipe', 'pipe'],
      windowsHide: true,
      shell: false
    });
    let failure;
    let bytes = 0;
    let timer;
    const stop = message => {
      if (failure) return;
      failure = new Error(message);
      if (child.pid) {
        const killer = spawn(path.join(process.env.SystemRoot || 'C:\\Windows', 'System32', 'taskkill.exe'),
          ['/PID', String(child.pid), '/T', '/F'], { stdio: 'ignore', windowsHide: true, shell: false });
        killer.on('error', error => {
          failure = new Error(`${message}; process-tree termination failed: ${error.message}. Check runner PID ${child.pid}.`);
          child.kill();
        });
        killer.on('exit', code => {
          if (code !== 0 && child.exitCode === null) {
            failure = new Error(`${message}; taskkill exited ${code}. Check runner PID ${child.pid}.`);
            child.kill();
          }
        });
      }
    };
    for (const stream of [child.stdout, child.stderr]) {
      stream.setEncoding('utf8');
      stream.on('data', text => {
        bytes += Buffer.byteLength(text);
        if (bytes > maxOutput) stop('Runner output exceeded 4 MiB; execution was stopped. Use smaller batches.');
        else onOutput(text);
      });
    }
    const abort = () => stop('MCP connection closed; runner execution was stopped.');
    signal?.addEventListener('abort', abort, { once: true });
    child.on('error', error => { clearTimeout(timer); signal?.removeEventListener('abort', abort); reject(error); });
    child.on('close', code => {
      clearTimeout(timer);
      signal?.removeEventListener('abort', abort);
      if (failure) reject(failure);
      else if (code === null) reject(new Error('Runner terminated without an exit code.'));
      else resolve(code);
    });
    timer = setTimeout(() => stop(`Runner timed out after ${request.timeoutSeconds}s; execution was stopped.`),
      request.timeoutSeconds * 1000);
    if (signal?.aborted) abort();
  });
}

export class RepositoryBridge {
  constructor(root = repoRoot, executor = executeRunner) {
    this.root = root;
    this.executor = executor;
    this.jobs = new Map();
    this.ready = new Set();
    this.builds = new Map();
    this.busy = false;
  }

  async read(relative, startLine = 1, lineCount = 200) {
    const filename = await resolveSafe(this.root, relative);
    if (!textExtensions.has(path.extname(filename).toLowerCase())) throw new Error('Only supported text files can be read.');
    const stat = await fs.stat(filename);
    if (!stat.isFile() || stat.size > 8 * 1024 * 1024) throw new Error('Text file must be a regular file no larger than 8 MiB.');
    const lines = (await fs.readFile(filename, 'utf8')).replace(/^\uFEFF/, '').split(/\r?\n/);
    return { path: relative, startLine, totalLines: lines.length,
      text: lines.slice(startLine - 1, startLine - 1 + lineCount).join('\n') };
  }

  async list(relative = '', offset = 0, limit = 100) {
    const directory = await resolveSafe(this.root, relative);
    const entries = (await fs.readdir(directory, { withFileTypes: true }))
      .filter(entry => !excluded.has(entry.name.toLowerCase()))
      .sort((a, b) => a.name.localeCompare(b.name));
    return { path: relative, total: entries.length, offset,
      entries: entries.slice(offset, offset + limit).map(entry => ({
        name: entry.name, kind: entry.isSymbolicLink() ? 'link' : entry.isDirectory() ? 'directory' : 'file'
      })) };
  }

  skill(product, skill) {
    if (!Object.hasOwn(products, product)) throw new Error('Unknown product.');
    if (!/^[A-Za-z][A-Za-z0-9_]{0,79}$/.test(skill)) throw new Error('Skill must contain only letters, digits and underscores, starting with a letter.');
    return path.join(product, 'Task', skill);
  }

  async writeSkill({ product, skill, filename, content, overwriteConfirmed = false }) {
    if (this.busy) throw new Error('A runner is active; wait before changing skill files.');
    this.busy = true;
    try {
      if (!this.ready.has(product)) throw new Error('Complete a successful product setup in this MCP session before generating a skill.');
      const directory = this.skill(product, skill);
      if (!/^[A-Za-z0-9_.-]+$/.test(filename) ||
          ![products[product].extension, '.md'].includes(path.extname(filename).toLowerCase())) {
        throw new Error('Only a source file for this product or a bilingual skill Markdown file is allowed.');
      }
      if (path.extname(filename).toLowerCase() === '.md') {
        const separator = /^---[ \t]*$/m.exec(content);
        if (!separator || !/[A-Za-z]/.test(content.slice(0, separator.index)) ||
            !/[\u3400-\u9fff]/.test(content.slice(separator.index + separator[0].length))) {
          throw new Error('Skill Markdown must have an English section followed by a --- separator and a Chinese section.');
        }
      }
      const target = await resolveSafe(this.root, path.join(directory, filename), true);
      await fs.mkdir(path.dirname(target), { recursive: true });
      await resolveSafe(this.root, path.join(directory, filename), true);
      await fs.writeFile(target, content, { encoding: 'utf8', flag: overwriteConfirmed ? 'w' : 'wx' });
      this.builds.delete(`${product}:${skill}`);
      return { path: path.relative(this.root, target), written: true };
    } finally {
      this.busy = false;
    }
  }

  async fingerprint(product, skill) {
    const relative = this.skill(product, skill);
    const directory = await resolveSafe(this.root, relative);
    const hash = createHash('sha256');
    const visit = async dir => {
      const entries = (await fs.readdir(dir, { withFileTypes: true })).sort((a, b) => a.name.localeCompare(b.name));
      for (const entry of entries) {
        if (excluded.has(entry.name.toLowerCase())) continue;
        const filename = path.join(dir, entry.name);
        await resolveSafe(this.root, path.relative(this.root, filename));
        if (entry.isSymbolicLink()) throw new Error('Skill build directories must not contain symlinks.');
        if (entry.isDirectory()) await visit(filename);
        else if ([products[product].extension, '.csproj', '.dll', '.h', '.hxx'].includes(path.extname(filename).toLowerCase())) {
          hash.update(path.relative(directory, filename));
          hash.update(await fs.readFile(filename));
        }
      }
    };
    await visit(directory);
    const dll = await resolveSafe(this.root, path.join(relative, `${skill}.dll`));
    if (!(await fs.stat(dll)).isFile()) throw new Error('Build did not produce the expected skill DLL.');
    return hash.digest('hex');
  }

  async start(request) {
    if (this.busy) throw new Error('Another runner is active. Poll its job before starting a new command.');
    this.busy = true;
    try {
      const { product, command, skill, userConfirmed, authorized } = request;
      if (!['environment', 'setup', 'ping', 'build', 'run'].includes(command)) throw new Error('Unknown runner command.');
      if (command !== 'environment' && !Object.hasOwn(products, product)) throw new Error('Unknown product.');
      if (command === 'ping' && product !== 'Tecnomatix') throw new Error('Only Tecnomatix provides ping.');
      const key = `${product}:${skill}`;
      if (command === 'build' || command === 'run') {
        if (!authorized) throw new Error('Confirm software/API authorization before building or running.');
        if (!this.ready.has(product)) throw new Error('Product setup must complete successfully in this MCP session first.');
        const directory = this.skill(product, skill);
        await resolveSafe(this.root, directory);
        if (command === 'build') {
          this.builds.delete(key);
          await resolveSafe(this.root, path.join(directory, `${skill}${products[product].extension}`));
        } else {
          if (!userConfirmed) throw new Error('Every run requires explicit user approval, including target scope and output/overwrite effects.');
          if (!this.builds.has(key) || this.builds.get(key) !== await this.fingerprint(product, skill)) {
            throw new Error('Run blocked: build this exact skill successfully in this MCP session, and rebuild after changes.');
          }
        }
      }
      if (command === 'setup') this.ready.delete(product);
      const job = { id: randomUUID(), product, command, skill, status: 'running', exitCode: null, output: '', error: null,
        controller: new AbortController() };
      for (const [id, old] of this.jobs) {
        if (this.jobs.size < 20) break;
        if (old.status !== 'running') this.jobs.delete(id);
      }
      this.jobs.set(job.id, job);
      job.completion = this.finish(job, { ...request, timeoutSeconds: request.timeoutSeconds ?? 120,
        args: request.args ?? [], argsJson: request.argsJson ?? {}, signal: job.controller.signal });
      return { jobId: job.id, status: job.status, message: 'Poll runner_status until completed or failed. Starting a job is not success.' };
    } catch (error) {
      this.busy = false;
      throw error;
    }
  }

  async finish(job, request) {
    try {
      job.exitCode = await this.executor(this.root, request, text => { job.output += text; });
      if (job.exitCode !== 0) throw new Error(`Existing runner exited ${job.exitCode}. Read its output and stop the affected workflow.`);
      if (job.command === 'setup') this.ready.add(job.product);
      if (job.command === 'build') this.builds.set(`${job.product}:${job.skill}`, await this.fingerprint(job.product, job.skill));
      job.status = 'completed';
    } catch (error) {
      job.error = error.message;
      job.status = 'failed';
    } finally {
      this.busy = false;
    }
  }

  status(id, offset = 0, limit = 16000) {
    const job = this.jobs.get(id);
    if (!job) throw new Error('Unknown or expired job ID. Jobs and setup/build state reset when the MCP server restarts.');
    return { jobId: id, product: job.product, command: job.command, status: job.status,
      exitCode: job.exitCode, error: job.error, output: job.output.slice(offset, offset + limit),
      nextOffset: Math.min(offset + limit, job.output.length), outputLength: job.output.length };
  }

  async close() {
    for (const job of this.jobs.values()) {
      if (job.status === 'running') job.controller.abort();
    }
    await Promise.all([...this.jobs.values()].map(job => job.completion));
  }
}
