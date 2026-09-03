param(
    [string]$Path = ".",
    [switch]$SummaryOnly
)

$ErrorActionPreference = "Stop"

$resolvedPath = (Resolve-Path -LiteralPath $Path).Path

$patterns = [ordered]@{
    "EF FromSqlRaw" = "FromSqlRaw"
    "EF FromSqlInterpolated" = "FromSqlInterpolated"
    "EF ExecuteSqlRaw" = "ExecuteSqlRaw"
    "EF ExecuteSqlInterpolated" = "ExecuteSqlInterpolated"
    "SqlCommand" = "SqlCommand"
    "StoredProcedure CommandType" = "CommandType\.StoredProcedure"
    "Dapper ExecuteAsync" = "\.ExecuteAsync\s*\("
    "Dapper QueryAsync" = "\.QueryAsync\s*\("
    "Dapper QueryFirst" = "\.QueryFirst"
    "Dapper QuerySingle" = "\.QuerySingle"
    "SQL EXEC" = "\bEXEC(?:UTE)?\b"
    "Create Procedure" = "CREATE\s+(?:OR\s+ALTER\s+)?PROCEDURE"
    "Create View" = "CREATE\s+(?:OR\s+ALTER\s+)?VIEW"
    "Create Function" = "CREATE\s+(?:OR\s+ALTER\s+)?FUNCTION"
    "Create Trigger" = "CREATE\s+(?:OR\s+ALTER\s+)?TRIGGER"
}

$includeExtensions = @(
    ".cs", ".sql", ".csproj", ".sqlproj", ".json", ".config", ".xml",
    ".ps1", ".psm1", ".yml", ".yaml", ".md"
)

$secretPattern = "(?i)(password|pwd|secret|token|apikey|api_key|connectionstring|connection string|user id|uid=|accountkey)"

$files = Get-ChildItem -LiteralPath $resolvedPath -Recurse -File -Force |
    Where-Object {
        $includeExtensions -contains $_.Extension.ToLowerInvariant() -and
        $_.FullName -notmatch "\\(bin|obj|\.git|\.vs|node_modules|packages)\\"
    }

$results = foreach ($file in $files) {
    $isSensitiveConfig = $file.Name -match "appsettings.*\.json|.*\.config"
    foreach ($entry in $patterns.GetEnumerator()) {
        $matches = Select-String -LiteralPath $file.FullName -Pattern $entry.Value -AllMatches -ErrorAction SilentlyContinue
        foreach ($match in $matches) {
            $lineText = $match.Line.Trim()
            if ($isSensitiveConfig -or $lineText -match $secretPattern) {
                $lineText = "[redacted config or secret-like line]"
            }

            [pscustomobject]@{
                Pattern = $entry.Key
                Path = $file.FullName
                LineNumber = $match.LineNumber
                Line = $lineText
            }
        }
    }
}

if ($SummaryOnly) {
    $results |
        Group-Object Pattern |
        Sort-Object Name |
        Select-Object Name, Count
} else {
    $results |
        Sort-Object Path, LineNumber, Pattern |
        Format-Table -AutoSize -Wrap
}
