param(
  [Parameter(Mandatory = $true)]
  [string]$PromptB64
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
& cc-deepseek -p "$promptText"
