[CmdletBinding()]
param(
    [ValidateRange(1, 10)][int]$MaxPushAttempts = 3
)

$ErrorActionPreference = 'Stop'

git config user.name 'github-actions[bot]'
if ($LASTEXITCODE -ne 0) { throw 'Cannot configure git user name.' }
git config user.email '41898282+github-actions[bot]@users.noreply.github.com'
if ($LASTEXITCODE -ne 0) { throw 'Cannot configure git user email.' }

git add -- data reports dashboard
if ($LASTEXITCODE -ne 0) { throw 'Cannot stage generated data.' }

git diff --cached --quiet
$diffExitCode = $LASTEXITCODE
if ($diffExitCode -eq 0) {
    Write-Host 'No data changes to commit.'
    exit 0
}
if ($diffExitCode -ne 1) { throw 'Cannot determine whether generated data changed.' }

git commit -m 'data: update prices'
if ($LASTEXITCODE -ne 0) { throw 'Cannot commit generated data.' }

for ($attempt = 1; $attempt -le $MaxPushAttempts; $attempt++) {
    git push
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Generated data pushed on attempt $attempt."
        exit 0
    }
    if ($attempt -eq $MaxPushAttempts) { break }

    Write-Warning "Push attempt $attempt failed; rebasing onto current origin/main."
    git fetch origin main
    if ($LASTEXITCODE -ne 0) { throw 'Cannot fetch current origin/main.' }
    git rebase origin/main
    if ($LASTEXITCODE -ne 0) {
        git rebase --abort
        throw 'Cannot rebase generated data onto current origin/main.'
    }
}

throw "Cannot push generated data after $MaxPushAttempts attempts."
