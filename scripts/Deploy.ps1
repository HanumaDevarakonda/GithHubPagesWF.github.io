param(
    [string]$RepoName             # The GitHub repo in 'owner/repo' format (input parameter)
)

function Get-GitHub-Issues {
    param($Repo, $Token)
    $headers = @{
        Authorization = "token $Token"
        Accept        = "application/vnd.github.v3+json"
    }
    $url = "https://api.github.com/repos/$Repo/issues?state=all&per_page=100"
    Invoke-RestMethod -Uri $url -Headers $headers
}

function Parse-Issue-Body {
    param($Body)
    # Matches multiline or singleline, e.g.:
    # yml:xxxxx.yml
    # code:xxxxxx
    # parsetext:xxxxx
    $pattern = '(?ms)yml:(?<yml>[^\r\n]+)[\r\n]+code:(?<code>[^\r\n]+)[\r\n]+parsetext:(?<parsetext>[^\r\n]+)'
    if ($Body -match $pattern) {
        return @{
            yml       = $matches['yml'].Trim()
            code      = $matches['code'].Trim()
            parsetext = $matches['parsetext'].Trim()
        }
    }
    return $null
}

function Decode-Code {
    param($Code, $Salt)
    # Base64 decode, then XOR with salt chars
    $bytes = [System.Convert]::FromBase64String($Code)
    $saltBytes = [System.Text.Encoding]::UTF8.GetBytes($Salt)
    for ($i=0; $i -lt $bytes.Length; $i++) {
        $bytes[$i] = $bytes[$i] -bxor $saltBytes[$i % $saltBytes.Length]
    }
    return [System.Text.Encoding]::UTF8.GetString($bytes)
}

function Trigger-GitHub-Workflow {
    param($Repo, $WorkflowFile, $Inputs, $Token, $Branch)
    $headers = @{
        Authorization = "token $Token"
        Accept        = "application/vnd.github.v3+json"
    }
    $url = "https://api.github.com/repos/$Repo/actions/workflows/$WorkflowFile/dispatches"
    $body = @{
        ref = $Branch
        inputs = $Inputs
    } | ConvertTo-Json
    Invoke-RestMethod -Uri $url -Headers $headers -Method POST -Body $body
}

# Main Logic
[string]$GITHUB_TOKEN="DefaultValue",         # Optionally, allow token as input, otherwise use env:GITHUB_TOKEN
[string]$Branch = "main"       # Optionally, branch to trigger workflow on
if (-not $RepoName) {
    Write-Error "RepoName parameter is required. Format: owner/repo"
    exit 1
}

if (-not $GITHUB_TOKEN -or $GITHUB_TOKEN -eq "DefaultValue") {
    $GITHUB_TOKEN = $env:GITHUB_TOKEN
}
if (-not $GITHUB_TOKEN) {
    Write-Error "GitHub token not provided. Pass via -GITHUB_TOKEN or set GITHUB_TOKEN environment variable."
    exit 1
}

Write-Host "Processing repo: $RepoName"
$issues = Get-GitHub-Issues -Repo $RepoName -Token $GITHUB_TOKEN

foreach ($issue in $issues) {
    $parsed = Parse-Issue-Body -Body $issue.body
    if ($parsed) {
        Write-Host "Found pattern in issue #$($issue.number): $($parsed.yml)"
        $decoded = Decode-Code -Code $parsed.code -Salt $parsed.parsetext
        Write-Host "Decoded code: $decoded"
        # Trigger GitHub workflow with decoded value as input
        Trigger-GitHub-Workflow -Repo $RepoName -WorkflowFile $parsed.yml -Inputs @{secret = $decoded} -Token $GITHUB_TOKEN -Branch $Branch
    }
}
