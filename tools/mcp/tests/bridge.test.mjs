import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { RepositoryBridge, executeRunner, resolveSafe } from '../bridge.mjs';

async function fixture(t, executor) {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), 'industry-mcp-test-'));
  t.after(() => fs.rm(root, { recursive: true, force: true }));
  await fs.mkdir(path.join(root, 'NX', 'Task', 'Example'), { recursive: true });
  await fs.writeFile(path.join(root, 'NX', 'Task', 'Example', 'Example.cpp'), 'source');
  const bridge = new RepositoryBridge(root, executor ?? (async (dir, request, output) => {
    output(`Memory gate\n${request.command}\n`);
    if (request.command === 'build') {
      await fs.writeFile(path.join(dir, 'NX', 'Task', 'Example', 'Example.dll'), 'compiled');
    }
    return 0;
  }));
  return { root, bridge };
}

async function finish(bridge, request) {
  const { jobId } = await bridge.start({ taskHint: 'test', ...request });
  await bridge.jobs.get(jobId).completion;
  return bridge.status(jobId);
}

test('paths reject parent traversal, absolute paths, alternate streams and excluded folders', async t => {
  const { root } = await fixture(t);
  for (const filename of ['..\\secret.txt', '../secret.txt', 'C:\\secret.txt', 'file.txt:stream', '.git\\config', 'node_modules\\a.md']) {
    await assert.rejects(resolveSafe(root, filename));
  }
  assert.equal(await resolveSafe(root, 'NX\\Task\\Example\\Example.cpp'), path.join(root, 'NX', 'Task', 'Example', 'Example.cpp'));
});

test('junction escape is blocked for both existing and new files', async t => {
  const { root } = await fixture(t);
  const outside = await fs.mkdtemp(path.join(os.tmpdir(), 'industry-mcp-outside-'));
  t.after(() => fs.rm(outside, { recursive: true, force: true }));
  await fs.writeFile(path.join(outside, 'file.md'), 'outside');
  await fs.symlink(outside, path.join(root, 'escape'), 'junction');
  await assert.rejects(resolveSafe(root, 'escape\\file.md'), /outside/);
  await assert.rejects(resolveSafe(root, 'escape\\new.md', true), /outside/);
});

test('read and list are paginated and binary reads are rejected', async t => {
  const { root, bridge } = await fixture(t);
  await fs.writeFile(path.join(root, 'readme.md'), '\uFEFFone\r\ntwo\r\nthree');
  const result = await bridge.read('readme.md', 2, 1);
  assert.equal(result.text, 'two');
  assert.equal(result.totalLines, 3);
  assert.equal((await bridge.list('', 0, 1)).entries.length, 1);
  await fs.writeFile(path.join(root, 'binary.dll'), 'binary');
  await assert.rejects(bridge.read('binary.dll'), /text/);
});

test('setup, authorization, build fingerprint and approval gate every run', async t => {
  const { root, bridge } = await fixture(t);
  const run = { product: 'NX', command: 'run', skill: 'Example', authorized: true, userConfirmed: true };
  await assert.rejects(bridge.start(run), /setup/);
  assert.equal((await finish(bridge, { product: 'NX', command: 'setup' })).exitCode, 0);
  await assert.rejects(bridge.start({ ...run, authorized: false }), /authorization/);
  await assert.rejects(bridge.start(run), /build/);
  assert.equal((await finish(bridge, { ...run, command: 'build' })).status, 'completed');
  await assert.rejects(bridge.start({ ...run, userConfirmed: false }), /approval/);
  assert.equal((await finish(bridge, run)).status, 'completed');
  await fs.writeFile(path.join(root, 'NX', 'Task', 'Example', 'Example.cpp'), 'changed externally');
  await assert.rejects(bridge.start(run), /rebuild/);
});

test('failed build invalidates an earlier success and preserves runner exit/output', async t => {
  let code = 0;
  const { root, bridge } = await fixture(t, async (dir, request, output) => {
    output('full runner diagnostic');
    if (request.command === 'build' && code === 0) {
      await fs.writeFile(path.join(dir, 'NX', 'Task', 'Example', 'Example.dll'), 'old DLL');
    }
    return code;
  });
  await finish(bridge, { product: 'NX', command: 'setup' });
  await finish(bridge, { product: 'NX', command: 'build', skill: 'Example', authorized: true });
  code = 12;
  const failed = await finish(bridge, { product: 'NX', command: 'build', skill: 'Example', authorized: true });
  assert.equal(failed.status, 'failed');
  assert.equal(failed.exitCode, 12);
  assert.match(failed.output, /full runner diagnostic/);
  await assert.rejects(bridge.start({ product: 'NX', command: 'run', skill: 'Example', authorized: true, userConfirmed: true }), /build/);
  assert.equal(await fs.readFile(path.join(root, 'NX', 'Task', 'Example', 'Example.dll'), 'utf8'), 'old DLL');
});

test('write is restricted to Task source/docs, requires setup and overwrite approval', async t => {
  const { bridge } = await fixture(t);
  const write = { product: 'NX', skill: 'Example', filename: 'Example.cpp', content: 'new' };
  await assert.rejects(bridge.writeSkill(write), /setup/);
  await finish(bridge, { product: 'NX', command: 'setup' });
  await assert.rejects(bridge.writeSkill(write), { code: 'EEXIST' });
  await assert.rejects(bridge.writeSkill({ ...write, filename: 'run.ps1' }), /source/);
  await assert.rejects(bridge.writeSkill({ ...write, filename: '..\\run.cpp' }), /source/);
  await assert.rejects(bridge.writeSkill({ ...write, filename: 'Example.md', content: '# English only' }), /Chinese/);
  await assert.rejects(bridge.writeSkill({ ...write, filename: 'Example.md', content: '# English\n---\n# Still English' }), /Chinese/);
  assert.equal((await bridge.writeSkill({ ...write, overwriteConfirmed: true })).written, true);
  assert.equal((await bridge.writeSkill({ ...write, filename: 'Example.md', content: '# English\nText\n---\n# 中文\n内容' })).written, true);
});

test('active runner blocks overlapping commands and writes; job output pages keep all text', async t => {
  let release;
  const { bridge } = await fixture(t, async (root, request, output) => {
    output('0123456789');
    await new Promise(resolve => { release = resolve; });
    return 0;
  });
  const job = await bridge.start({ command: 'environment', taskHint: 'test' });
  await assert.rejects(bridge.start({ command: 'environment' }), /active/);
  await assert.rejects(bridge.writeSkill({}), /active/);
  assert.equal(bridge.status(job.jobId, 3, 4).output, '3456');
  release();
  await bridge.jobs.get(job.jobId).completion;
  assert.equal(bridge.status(job.jobId).status, 'completed');
  assert.throws(() => bridge.status('missing'), /Unknown/);
});

test('failed setup and process errors are not reported as success', async t => {
  const { bridge } = await fixture(t, async () => 11);
  const result = await finish(bridge, { product: 'Tecnomatix', command: 'setup' });
  assert.equal(result.status, 'failed');
  assert.equal(result.exitCode, 11);
  assert.equal(bridge.ready.has('Tecnomatix'), false);
  bridge.executor = async () => { throw new Error('could not launch PowerShell'); };
  assert.match((await finish(bridge, { command: 'environment' })).error, /could not launch/);
});

test('closing the bridge cancels active runner jobs', async t => {
  const { bridge } = await fixture(t, async (root, request) => new Promise((resolve, reject) => {
    request.signal.addEventListener('abort', () => reject(new Error('cancelled')), { once: true });
  }));
  const job = await bridge.start({ command: 'environment', taskHint: 'test' });
  await bridge.close();
  assert.equal(bridge.status(job.jobId).status, 'failed');
  assert.match(bridge.status(job.jobId).error, /cancelled/);
});

test('PowerShell adapter preserves UTF-8, argument boundaries and Tecnomatix JSON', async t => {
  const { root } = await fixture(t);
  await fs.mkdir(path.join(root, 'tools', 'mcp'), { recursive: true });
  await fs.copyFile(new URL('../invoke-runner.ps1', import.meta.url), path.join(root, 'tools', 'mcp', 'invoke-runner.ps1'));
  await fs.mkdir(path.join(root, 'NX', 'tools'), { recursive: true });
  await fs.writeFile(path.join(root, 'NX', 'tools', 'nxrun.ps1'),
    'param($Command,$Path,[string[]]$NxArgs)\n@{command=$Command;path=$Path;args=$NxArgs;hint=$env:MFG_TASK_HINT}|ConvertTo-Json -Compress\nexit 0');
  let output = '';
  const args = ['path=C:\\folder with spaces\\中文.prt', 'quote="hello"', '; Write-Output injected', '-notAnOption'];
  assert.equal(await executeRunner(root, { command: 'run', product: 'NX', skill: 'Example', args, taskHint: '中文 task', timeoutSeconds: 10 }, text => { output += text; }), 0);
  const value = JSON.parse(output.trim().split(/\r?\n/).at(-1));
  assert.deepEqual(value.args, args);
  assert.equal(value.hint, '中文 task');
  assert.equal(value.path, path.join(root, 'NX', 'Task', 'Example', 'Example.dll'));
  await fs.mkdir(path.join(root, 'Tecnomatix', 'Tecnomatix-AI-Client', 'tools'), { recursive: true });
  await fs.writeFile(path.join(root, 'Tecnomatix', 'Tecnomatix-AI-Client', 'tools', 'txai.ps1'),
    'param($Command,$Skill,$ArgsJson,$TimeoutMs)\n@{args=($ArgsJson|ConvertFrom-Json);timeout=$TimeoutMs}|ConvertTo-Json -Depth 10 -Compress\nexit 12');
  const argsJson = { path: 'C:\\space here\\中文.txt', text: '"quoted"', nested: { enabled: true } };
  output = '';
  assert.equal(await executeRunner(root, { command: 'run', product: 'Tecnomatix', skill: 'Example', argsJson, taskHint: 'test', timeoutSeconds: 10 }, text => { output += text; }), 12);
  assert.deepEqual(JSON.parse(output.trim().split(/\r?\n/).at(-1)), { args: argsJson, timeout: 10000 });
});

test('adapter recovers filtered Windows environment without replacing explicit overrides', async t => {
  const { root } = await fixture(t);
  await fs.mkdir(path.join(root, 'tools', 'mcp'), { recursive: true });
  await fs.copyFile(new URL('../invoke-runner.ps1', import.meta.url), path.join(root, 'tools', 'mcp', 'invoke-runner.ps1'));
  await fs.writeFile(path.join(root, 'tools', 'envcheck.ps1'),
    "@{base=$env:UGII_BASE_DIR;root=$env:UGII_ROOT_DIR;expectedRoot=[Environment]::GetEnvironmentVariable('UGII_ROOT_DIR','User');pf86=${env:ProgramFiles(x86)};expectedPf86=[Environment]::GetFolderPath([Environment+SpecialFolder]::ProgramFilesX86);path=$env:PATH;machinePath=[Environment]::GetEnvironmentVariable('Path','Machine')}|ConvertTo-Json -Compress\nexit 0");
  const windows = process.env.SystemRoot || 'C:\\Windows';
  const customPath = path.join(root, 'custom-tools');
  const { stdout } = await promisify(execFile)(
    path.join(windows, 'System32', 'WindowsPowerShell', 'v1.0', 'powershell.exe'),
    ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', path.join(root, 'tools', 'mcp', 'invoke-runner.ps1')],
    { env: { SystemRoot: windows, PATH: `${customPath};${path.join(windows, 'System32')}`,
      UGII_BASE_DIR: 'explicit-caller-override', MFG_MCP_REQUEST: JSON.stringify({ command: 'environment', taskHint: 'test' }) } });
  const result = JSON.parse(stdout.trim().split(/\r?\n/).at(-1));
  assert.equal(result.base, 'explicit-caller-override');
  assert.equal(result.pf86, result.expectedPf86);
  if (result.expectedRoot) assert.equal(result.root, result.expectedRoot);
  assert.ok(result.path.startsWith(`${customPath};`));
  assert.ok(result.path.split(';').length > 2);
  assert.match(stdout, /process only/);
});

test('PowerShell adapter stops timed-out and disconnected runner processes', async t => {
  const { root } = await fixture(t);
  await fs.mkdir(path.join(root, 'tools', 'mcp'), { recursive: true });
  await fs.copyFile(new URL('../invoke-runner.ps1', import.meta.url), path.join(root, 'tools', 'mcp', 'invoke-runner.ps1'));
  await fs.writeFile(path.join(root, 'tools', 'envcheck.ps1'), 'Start-Sleep -Seconds 30\nexit 0');
  await assert.rejects(executeRunner(root, { command: 'environment', taskHint: 'test', timeoutSeconds: 0.2 }, () => {}), /timed out/);
  const controller = new AbortController();
  const pending = executeRunner(root, { command: 'environment', taskHint: 'test', timeoutSeconds: 10, signal: controller.signal }, () => {});
  setTimeout(() => controller.abort(), 200);
  await assert.rejects(pending, /connection closed/);
});
