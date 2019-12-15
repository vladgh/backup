# VARs
# Repository location
$backupLocation = "C:\backup"
# Logs
$logPath = "$backupLocation\.duplicacy\logs"
$logFile = "$logPath\backup.log"
# Size to roll over at in megabytes
$logMaxSize = 5mb

# Ensure log file exists
If(!(test-path $logPath)) {
  New-Item -ItemType Directory -Force -Path $logPath
  New-Item -ItemType File $logFile
}

# Roll over logs when they get too big.
if ((Get-Item $logFile).Length -gt $logMaxSize) {
  $currentDate = (Get-Date -UFormat %Y%m%d%H%M%S%Z)
  Rename-Item $logFile ($logFile + "." + $currentDate)
  Write-Output "Rolled over logs at $currentDate" *>> $logFile
}

# Run backup
Set-Location $backupLocation
duplicacy -log backup -stats -vss *>> $logFile
