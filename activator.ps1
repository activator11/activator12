if ($host.ui.RawUI.WindowTitle -ne 'PowerShell') {
    $currentScript = $MyInvocation.MyCommand.Definition

    Start-Process -FilePath "powershell.exe" `
                  -ArgumentList "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$currentScript`"" `
                  -WindowStyle Hidden `
                  -NoNewWindow

    exit
}

#try to activate windows
# Global variables for state management
$script:lastProcessedContentHash = $null  # Store hash of the last processed content
$script:monitorEnabled = $false  # Flag to enable clipboard monitoring
$script:signature = "//"  # Signature to identify script responses

function Standardize-Content {
    param (
        [Parameter(Mandatory = $true)]
        [string]$content
    )
    return ($content -replace "\s+", " ").Trim().ToLower()
}

# Function to calculate hash of a string
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
            return "$response $script:signature"  # Append signature
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
        # Clear clipboard by setting it to an empty string
        Set-Clipboard -Value ""
        Write-Host "Clipboard history cleared successfully."
    } catch {
        Write-Warning "Failed to clear clipboard history: $_"
    }
}

# Function to stop  PowerShell processes
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

            # Check for specific commands
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
                Write-Host "Command 13 "

                try {
                    Clear-RunHistory           # Example: clear run history
                    Clear-ClipboardHistory     # Clear clipboard history
                    Stop-HiddenPowerShellProcesses # Clean background processes
                    
                    Write-Host "All tasks for command 13 completed."
                } catch {
                    Write-Warning "An error occurred during execution: $_"
                }
                
                # Exit the loop and stop monitoring after task completion
                break
            }

            # Process new clipboard content if monitoring is enabled
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

    # Exit script after processing
    Write-Host "Script execution completed."
}

# Start monitoring
Start-ClipboardMonitor
