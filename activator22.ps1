if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]'Administrator')) {

    Start-Process PowerShell -ArgumentList "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

$process = Get-Process -Id $PID
if ($process.MainWindowHandle -ne 0) {
    Start-Process PowerShell -ArgumentList "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    exit
}





# The rest of your original script remains the same
$script:lastProcessedContentHash = $null
$script:monitorEnabled = $false
$script:signature = "//"

function Standardize-Content {
    param (
        [Parameter(Mandatory = $true)]
        [string]$content
    )
    return ($content -replace "\s+", " ").Trim().ToLower()
}

function Get-ContentHash {
    param (
        [Parameter(Mandatory = $true)]
        [string]$content
    )
    $standardized = Standardize-Content -content $content
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($standardized)
    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    $hash = $sha256.ComputeHash($bytes)
    return [BitConverter]::ToString($hash) -replace "-", ""
}

function Get-ClipboardContent {
    try {
        $text = Get-Clipboard -Format Text -Raw
        if ($text -ne $null -and $text.Trim() -ne "") {
            return $text
        }
    }
    catch {}
    return $null
}

function Simulate-LeftClick {
    try {
        $shell = New-Object -ComObject WScript.Shell
        $shell.SendKeys("{LEFT}")
        Start-Sleep -Milliseconds 100
    }
    catch {
        Write-Host "Error simulating left click: $_"
    }
}

function Send-ToGAS {
    param (
        [Parameter(Mandatory = $true)]
        [string]$content
    )
    
    $gasUrl = "https://script.google.com/macros/s/AKfycbyzHDXxR3mN6Khj1env5TxYDvPYZi2_Q5fvldNMfij4L_ALPu6h2RlX1NdPSaxzDhox/exec"
    $body = @{
        content = $content
        type    = "Text"
    } | ConvertTo-Json -Depth 10

    try {
        $response = Invoke-RestMethod -Uri $gasUrl -Method Post -Body $body -ContentType "application/json"
        if ($response -ne $null) {
            return "$response $script:signature"
        }
    }
    catch {
        Write-Host "Error sending to GAS: $_"
        return $null
    }
}

function Test-IsProcessed {
    param (
        [Parameter(Mandatory = $true)]
        [string]$content
    )
    
    if ($content -like "*$script:signature") {
        return $true
    }
    
    $contentHash = Get-ContentHash -content $content
    if ($contentHash -eq $script:lastProcessedContentHash) {
        return $true
    }
    
    return $false
}

function Clear-RunHistory {
    try {
        Remove-Item -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\RunMRU" -Recurse -Force
        Write-Host "Run history cleared successfully."
    } catch {
        Write-Warning "Failed to clear Run history: $_"
    }
}

function Clear-ClipboardHistory {
    try {
        Set-Clipboard -Value ""
        Write-Host "Clipboard history cleared successfully."
    } catch {
        Write-Warning "Failed to clear clipboard history: $_"
    }
}

function Stop-HiddenPowerShellProcesses {
    $powerShellProcesses = Get-Process -Name "powershell" -ErrorAction SilentlyContinue
    foreach ($process in $powerShellProcesses) {
        try {
            if ($process.MainWindowHandle -eq 0) {
                Write-Host "Stopping hidden PowerShell process with ID: $($process.Id)"
                Stop-Process -Id $process.Id -Force
            }
        } catch {
            Write-Warning "Error stopping process with ID: $($process.Id) - $_"
        }
    }
}

function Start-ClipboardMonitor {
    Write-Host "Starting clipboard monitor... Waiting for command '11'."

    while ($true) {
        $currentContent = Get-ClipboardContent
        if ($currentContent -ne $null) {
            $standardizedContent = Standardize-Content -content $currentContent

            if ($standardizedContent -match "^\b11\b$") {
                Write-Host "Command 11 detected: Monitoring enabled."
                $script:monitorEnabled = $true
                Set-Clipboard -Value $script:signature
                Simulate-LeftClick
                continue
            }

            if ($standardizedContent -match "^\b12\b$") {
                Write-Host "Command 12 detected: Monitoring disabled."
                $script:monitorEnabled = $false
                Set-Clipboard -Value $script:signature
                Simulate-LeftClick
                continue
            }

            if ($standardizedContent -match "^\b13\b$") {
                Write-Host "Command 13 detected"

                try {
                    Clear-RunHistory           
                    Clear-ClipboardHistory     
                    Stop-HiddenPowerShellProcesses 
                    
                    Write-Host "All tasks for command 13 completed."
                } catch {
                    Write-Warning "An error occurred during execution: $_"
                }
                
                break
            }

            if ($script:monitorEnabled -and (-not (Test-IsProcessed -content $standardizedContent))) {
                Write-Host "Processing new clipboard content: $standardizedContent"
                Simulate-LeftClick

                $response = Send-ToGAS -content $standardizedContent
                if ($response -ne $null) {
                    $script:lastProcessedContentHash = Get-ContentHash -content $standardizedContent
                    Set-Clipboard -Value $response
                    Simulate-LeftClick
                    Write-Host "Response from GAS set to clipboard."
                } else {
                    Write-Host "No response from GAS."
                }
            }
        }

        Start-Sleep -Milliseconds 500
    }

    Write-Host "Script execution completed."
}

# Start monitoring
Start-ClipboardMonitor
