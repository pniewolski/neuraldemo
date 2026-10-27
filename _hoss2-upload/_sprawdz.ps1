$e = $null
$null = [System.Management.Automation.Language.Parser]::ParseFile('C:\p\PhpstormProjects\_hoss2-upload\wgraj.ps1', [ref]$null, [ref]$e)
if ($e -and $e.Count -gt 0) {
    Write-Output ("BLEDY=" + $e.Count)
    $e | ForEach-Object { Write-Output ("  linia " + $_.Extent.StartLineNumber + ": " + $_.Message) }
} else {
    Write-Output "SKLADNIA_OK"
}

