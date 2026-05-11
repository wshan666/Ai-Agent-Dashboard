param(
  [Parameter(Mandatory = $true)]
  [string]$PromptB64,

  [string]$SessionId = 'dashboard-lobster'
)

$ErrorActionPreference = 'Stop'
[Console]::InputEncoding = [Text.Encoding]::UTF8
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$OutputEncoding = [Text.Encoding]::UTF8

if ($PromptB64.StartsWith('@')) {
  $promptPath = $PromptB64.Substring(1)
  $promptText = Get-Content -LiteralPath $promptPath -Raw -Encoding UTF8
} else {
  $promptText = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($PromptB64))
}
$promptFile = Join-Path ([IO.Path]::GetTempPath()) ("dashboard-openclaw-" + [Guid]::NewGuid().ToString("N") + ".txt")
$runnerFile = Join-Path ([IO.Path]::GetTempPath()) ("dashboard-openclaw-runner-" + [Guid]::NewGuid().ToString("N") + ".cjs")

try {
  [IO.File]::WriteAllText($promptFile, $promptText, [Text.UTF8Encoding]::new($false))
  $runner = @'
const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');

const promptFile = process.argv[2];
const sessionId = process.argv[3] || 'dashboard-lobster';
const prompt = fs.readFileSync(promptFile, 'utf8');
const appData = process.env.APPDATA || '';
const openclawMjs = path.join(appData, 'npm', 'node_modules', 'openclaw', 'openclaw.mjs');
const args = [openclawMjs, 'agent', '--local', '--message', prompt, '--session-id', sessionId, '--json'];
const result = spawnSync('node', args, { encoding: 'utf8', windowsHide: true, maxBuffer: 20 * 1024 * 1024 });
if (result.stdout) process.stdout.write(result.stdout);
if (result.stderr) process.stderr.write(result.stderr);
process.exit(result.status == null ? 1 : result.status);
'@
  [IO.File]::WriteAllText($runnerFile, $runner, [Text.UTF8Encoding]::new($false))
  & node $runnerFile $promptFile $SessionId
} finally {
  Remove-Item -LiteralPath $promptFile -Force -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath $runnerFile -Force -ErrorAction SilentlyContinue
}
