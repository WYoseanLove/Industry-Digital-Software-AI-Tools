import test from 'node:test';
import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { Client } from '@modelcontextprotocol/sdk/client/index.js';
import { StdioClientTransport } from '@modelcontextprotocol/sdk/client/stdio.js';

async function connect(t, inheritEnvironment = true) {
  const transport = new StdioClientTransport({
    command: process.execPath,
    args: [fileURLToPath(new URL('../server.mjs', import.meta.url))],
    env: inheritEnvironment ? { ...process.env } : undefined,
    stderr: 'pipe'
  });
  const client = new Client({ name: 'repository-mcp-test', version: '1.0.0' });
  await client.connect(transport);
  t.after(() => client.close());
  return client;
}
const decode = result => JSON.parse(result.content[0].text);

test('generated Claude configuration is valid JSON with absolute executable and server paths', async () => {
  const filename = fileURLToPath(new URL('../server.mjs', import.meta.url));
  const { stdout, stderr } = await promisify(execFile)(process.execPath, [filename, '--print-config']);
  assert.equal(stderr, '');
  assert.deepEqual(JSON.parse(stdout), { mcpServers: {
    'industry-digital-software': { command: process.execPath, args: [filename] }
  } });
});

test('real stdio handshake, tool discovery, repository read and invalid calls', async t => {
  const client = await connect(t);
  assert.equal(client.getServerVersion().name, 'industry-digital-software-ai-tools');
  const tools = await client.listTools();
  assert.deepEqual(tools.tools.map(tool => tool.name).sort(),
    ['repository_context', 'repository_list', 'repository_read', 'runner_start', 'runner_status', 'skill_write'].sort());
  const context = decode(await client.callTool({ name: 'repository_context', arguments: {} }));
  assert.ok(context.documents.some(doc => doc.path === 'README.md'));
  assert.ok(context.documents.some(doc => doc.path === 'Memory\\learned.md'));
  const read = decode(await client.callTool({ name: 'repository_read', arguments: { path: 'tools\\mcp\\package.json', lineCount: 3 } }));
  assert.match(read.text, /industry-digital/);
  assert.equal((await client.callTool({ name: 'repository_read', arguments: { path: '..\\secret.txt' } })).isError, true);
  assert.equal((await client.callTool({ name: 'runner_start', arguments: {
    product: 'NX', command: 'run', skill: 'Example', taskHint: 'test', authorized: true, userConfirmed: true
  } })).isError, true);
  assert.equal((await client.callTool({ name: 'runner_start', arguments: {
    product: 'NX', command: 'setup', taskHint: 'test', argsJson: { forbidden: true }
  } })).isError, true);
});

for (const inheritEnvironment of [true, false]) {
test(`live environment and NX setup with ${inheritEnvironment ? 'inherited' : 'minimal'} MCP environment`, {
  skip: process.env.MFG_MCP_LIVE_TEST !== '1', timeout: 180000
}, async t => {
  const client = await connect(t, inheritEnvironment);
  async function run(arguments_) {
    const start = await client.callTool({ name: 'runner_start', arguments: arguments_ });
    assert.notEqual(start.isError, true, start.content[0].text);
    const { jobId } = decode(start);
    let status;
    do {
      await new Promise(resolve => setTimeout(resolve, 250));
      status = decode(await client.callTool({ name: 'runner_status', arguments: { jobId, limit: 32000 } }));
    } while (status.status === 'running');
    assert.equal(status.status, 'completed', JSON.stringify(status));
    assert.equal(status.exitCode, 0);
    let output = status.output;
    while (status.nextOffset < status.outputLength) {
      status = decode(await client.callTool({ name: 'runner_status', arguments: { jobId, offset: status.nextOffset, limit: 32000 } }));
      output += status.output;
    }
    return output;
  }
  const environment = await run({ command: 'environment', taskHint: 'MCP environment check', timeoutSeconds: 120 });
  assert.match(environment, /Build prerequisites/);
  assert.ok(/NX\s+USABLE/.test(environment), environment.slice(-5000));
  assert.ok(!/\[X\].*(?:\.NET|MSVC)/.test(environment), environment.slice(-5000));
  assert.ok(!environment.includes('Memory format:'), 'Memory format warnings must be fixed.');
  assert.match(environment, /MEMORY GATE/);
  const setup = await run({ product: 'NX', command: 'setup', taskHint: 'MCP NX setup', timeoutSeconds: 120 });
  assert.match(setup, /SETUP OK/);
  assert.match(setup, /MEMORY GATE/);
});
}
