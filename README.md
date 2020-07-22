# Vlad's Duplicacy Backup Scripts

![Build Status](https://github.com/vladgh/backup/workflows/CI/badge.svg)

## Install Duplicacy

Download latest release from <https://github.com/gilbertchen/duplicacy/releases> and add it to PATH

Linux

```sh
sudo wget -O /usr/local/bin/duplicacy https://github.com/gilbertchen/duplicacy/releases/download/v2.5.2/duplicacy_linux_x64_2.5.2 && sudo chmod 755 /usr/local/bin/duplicacy
```

MacOS

```sh
wget -O /usr/local/bin/duplicacy https://github.com/gilbertchen/duplicacy/releases/download/v2.5.2/duplicacy_osx_x64_2.5.2 && chmod 755 /usr/local/bin/duplicacy
```

Windows

```powershell
# Requires Administrator rights
Invoke-WebRequest -Uri "https://github.com/gilbertchen/duplicacy/releases/download/v2.5.2/duplicacy_win_x64_2.5.2.exe" -OutFile "C:\Windows\System32\duplicacy.exe"
```

## Initialize the repository

Pick the desired location for the .duplicacy folder, this will be your repository root. Defaults to your user's home.
When you initialize the repository, it will ask for the encryption password and the path to the RSA key used by SFTP.

```sh
duplicacy init -encrypt MyID sftp://user@192.168.1.2//path/to/backup/storage
```

By default Duplicacy will follow the first-level symlinks (those under the root of the repository).
Symlinks located under any subdirectories of the repository will be backed up as symlinks and will not be followed.

For example, on Windows:

```powershell
mkdir C:\backup
cd C:\backup
cmd /c mklink /D myname C:\Users\myname
cmd /c mklink /D docs D:\DOCs
```

## Configure the repository

```sh
duplicacy set -storage default -key password -value 'MyPassword'
duplicacy set -storage default -key ssh_key_file -value '/path/to/.ssh/duplicacy_rsa'
```

Place the appropriate filters file inside the `.duplicacy` folder

```sh
wget -O ~/.duplicacy/filters https://github.com/vladgh/backup/raw/master/filters/osx
```

For Windows

```powershell
Invoke-WebRequest -Uri "https://github.com/vladgh/backup/raw/master/filters/windows" -OutFile "C:\backup\.duplicacy\filters"
```

## Backup

```sh
duplicacy -log backup -stats -vss
```

## VBackup Script OSX

Download the OSX/Linux backup script `vbackup.sh`, add it to PATH and make it executable

```sh
wget -O /usr/local/bin/vbackup https://github.com/vladgh/backup/raw/master/vbackup.sh
chmod a+x /usr/local/bin/vbackup
```

Use a dotenv file for secrets and other settings

```sh
tee ~/.duplicacy/.env << CONFIG
SLACK_ALERTS_WEBHOOK='https://hooks.slack.com/services/xxxxxxxxxx'
CONFIG
chmod 600 ~/.duplicacy/.env
```

Update the paths and settings in the sample .plist launch script below, copy it to ~/Library/LaunchAgents and load it (-w enables it at the next boot)

```sh
# Install launch agent
tee ~/Library/LaunchAgents/duplicacy.plist << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
  <dict>
    <key>Label</key>
    <string>duplicacy.startup</string>
    <key>ProgramArguments</key>
    <array>
      <string>/usr/local/bin/bash</string>
      <string>/usr/local/bin/vbackup</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>UserName</key>
    <string>vlad</string>
    <key>GroupName</key>
    <string>staff</string>
    <key>WorkingDirectory</key>
    <string>/Users/vlad</string>
    <key>StandardErrorPath</key>
    <string>/dev/null</string>
    <key>StandardOutPath</key>
    <string>/dev/null</string>
    <key>StartInterval</key>
    <integer>3600</integer>
  </dict>
</plist>
EOF

# Load/Unload agent
launchctl load -w ~/Library/LaunchAgents/duplicacy.plist
```

Restart with

```sh
launchctl unload -w ~/Library/LaunchAgents/duplicacy.plist && launchctl load -w ~/Library/LaunchAgents/duplicacy.plist
```

## VBackup Script Linux

Download the OSX/Linux backup script `vbackup.sh`, add it to PATH and make it executable

```sh
sudo wget -O /usr/local/bin/vbackup https://github.com/vladgh/backup/raw/master/vbackup.sh
sudo chmod a+x /usr/local/bin/vbackup
```

Use a dotenv file for secrets and other settings

```sh
tee ~/.duplicacy/.env << CONFIG
SLACK_ALERTS_WEBHOOK='https://hooks.slack.com/services/xxxxxxxxxx'
CONFIG
chmod 600 ~/.duplicacy/.env
```

Use SystemD timers to trigger the backup service

```sh
tee ~/.config/systemd/user/vbackup.service << 'EOF'
[Unit]
Description=Run VBackup
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
WorkingDirectory=%h
ExecStart=/usr/local/bin/vbackup
EOF

tee /home/vlad/.config/systemd/user/vbackup.timer  << 'EOF'
[Unit]
Description=Run VBackup

[Timer]
OnBootSec=15min
OnUnitActiveSec=60min

[Install]
WantedBy=timers.target
EOF

systemctl --user --now enable vbackup.timer
systemctl --user list-timers --all
```

Alternatively, create a cronjob to run the script as your user, at some interval

```sh
sudo tee /etc/cron.d/vbackup << CONFIG
10 * * * * vlad /usr/local/bin/vbackup.sh >/dev/null 2>&1
CONFIG
```

## VBackup Script Windows

Download the Windows backup script `vbackup.ps1`

```powershell
Invoke-WebRequest -Uri "https://github.com/vladgh/backup/raw/master/vbackup.ps1" -OutFile "C:\backup\vbackup.ps1"
```

Import the sample xml below into the Task Scheduler to run the powershell script at some interval with elevated privileges. Modify as needed!

```xml
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.3" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo>
    <Author>MyPC\MyName</Author>
    <URI>\DuplicacyBackup</URI>
  </RegistrationInfo>
  <Triggers>
    <TimeTrigger>
      <Repetition>
        <Interval>PT1H</Interval>
        <Duration>P10000D</Duration>
        <StopAtDurationEnd>true</StopAtDurationEnd>
      </Repetition>
      <StartBoundary>2019-05-02T06:00:00+02:00</StartBoundary>
      <Enabled>true</Enabled>
      <RandomDelay>PT5M</RandomDelay>
    </TimeTrigger>
  </Triggers>
  <Principals>
    <Principal id="Author">
      <UserId>MyPC\MyName</UserId>
      <LogonType>Password</LogonType>
      <RunLevel>HighestAvailable</RunLevel>
    </Principal>
  </Principals>
  <Settings>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <DisallowStartIfOnBatteries>true</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
    <AllowHardTerminate>true</AllowHardTerminate>
    <StartWhenAvailable>true</StartWhenAvailable>
    <RunOnlyIfNetworkAvailable>false</RunOnlyIfNetworkAvailable>
    <IdleSettings>
      <StopOnIdleEnd>true</StopOnIdleEnd>
      <RestartOnIdle>false</RestartOnIdle>
    </IdleSettings>
    <AllowStartOnDemand>true</AllowStartOnDemand>
    <Enabled>true</Enabled>
    <Hidden>false</Hidden>
    <RunOnlyIfIdle>false</RunOnlyIfIdle>
    <DisallowStartOnRemoteAppSession>false</DisallowStartOnRemoteAppSession>
    <UseUnifiedSchedulingEngine>true</UseUnifiedSchedulingEngine>
    <WakeToRun>false</WakeToRun>
    <ExecutionTimeLimit>PT72H</ExecutionTimeLimit>
    <Priority>7</Priority>
  </Settings>
  <Actions Context="Author">
    <Exec>
      <Command>powershell.exe</Command>
      <Arguments>-NoProfile -ExecutionPolicy Bypass -File "C:\backup\vbackup.ps1" -Verb RunAs; quit</Arguments>
    </Exec>
  </Actions>
</Task>
```

Manually trigger scheduled task

```powershell
Start-ScheduledTask -TaskName "DuplicacyBackup"
```

---

## Recovery

Create a folder to restore files

```sh
mkdir -p /tmp/restore
cd /tmp/restore
```

Initialize with THE SAME ID AND PASSWORD as the one in the storage

```sh
duplicacy init -encrypt MyID sftp://user@192.168.1.2//path/to/backup/storage
```

Restore the wanted path from the wanted revision

```sh
duplicacy -log restore -r 604 -stats 'Dropbox/Projects/*'
```

Look for files, use the list command and grep

```sh
duplicacy list -r 12 -files | grep pattern
duplicacy list -r 1-100 -files | grep pattern
```

For Windows

```powershell
duplicacy list -r 12 -files | Select-String -Pattern myFile
duplicacy list -r 1-100 -files | Select-String -Pattern myFile
```

## Restore local default storage from remote

```sh
# With B2 configured in preferences, copy from B2 to default, with bit-identical and set the id and path
duplicacy add -e -copy B2 -bit-identical default MyID /path/to/backup/storage
```

## Fix corrupted snapshot

Make sure no other backups are running and delete the corrupted snapshot

```sh
duplicacy check -a -tabular  # Check all snapshots (this is better than individual id checks, because of deduplication, when the corrupted chunks could belong to different IDs)
duplicacy check -tabular -id VDev -r 1510-1520  # OR check a range of snapshots
duplicacy check -tabular -storage B2 -id VDev -r 1510-1520  # OR check a range of snapshots for a single ID on a remote storage

duplicacy prune -exhaustive -exclusive -id VDev -r 1515  # Remove the corrupted snapshot

# IF `duplicacy check -a -tabular` fails with:
# All chunks referenced by snapshot VDev at revision 5114 exist
# Chunk cc86bc8351524fa2d17f65abd38b8609489a20410370965291de881b21b15226 can't be found
# Go and delete the `snapshots/VDev/5115` file
# Then run `duplicacy prune -exhaustive -exclusive`
```

---

## Miscellaneous

### Create log rotation script on Mac OS

```sh
sudo tee /etc/newsyslog.d/duplicacy.conf << CONFIG
# logfilename                            [owner:group]   mode  count  size  when  flags [/pid_file] [sig_num]
/Users/vlad/.duplicacy/logs/backup.log   vlad:staff      644   10     1000  *     NJ
CONFIG
```

### Log rotation in Linux

```sh
sudo tee /etc/logrotate.d/duplicacy << CONFIG
/home/vlad/.duplicacy/logs/backup.log {
  daily
  rotate 14
  compress
  delaycompress
  missingok
  notifempty
  create 644 vlad vlad
}
CONFIG
```

### Full disk access on Mac OS

This script needs Full Disk Access so we need to add `/usr/local/bin/bash` to Security & Privacy - Privacy - Full Disk Access (Use CMD+SHIFT+. to show hidden files in the Open file dialog).
The .plist file should run with ProgramArguments, `bash` being the first one (or environment variables).

### Linux tail Logs

```sh
tail -f ~/.duplicacy/logs/backup.log
grep -A 1 -e 'INFO BACKUP_END' ~/.duplicacy/logs/backup.log
```

### PowerShell tail logs

```powershell
Get-Content C:\backup\.duplicacy\logs\backup.log -Tail 20 -Wait
```

### PowerShell pattern in logs

```powershell
# All
Get-Content C:\backup\.duplicacy\logs\backup.log | Select-String -Pattern 'INFO BACKUP_END' -Context 0,1
# In the last 1000 lines
Get-Content C:\backup\.duplicacy\logs\backup.log -Tail 1000 | Select-String -Pattern 'INFO BACKUP_END' -Context 0,1
```

### Mount backup drive, and save credentials on Windows

In Windows 10, the credentials need to include the workgroup (ex: WORKGROUP\myname)

```powershell
net use Z: \\192.168.1.2\PathToBackup /savecred /persistent:yes
```

### Clone storage on Backblaze B2

Create a duplicate encrypted storage on Backblaze B2

```sh
duplicacy add -encrypt -copy default -bit-identical B2 MyID b2://vladgh
```

Add keys and passwords to preferences

```sh
duplicacy set -storage default -key password -value 'mypwd'
duplicacy set -storage B2 -key b2_id -value 'xxxxx'
duplicacy set -storage B2 -key b2_key -value 'xxxxx'
duplicacy set -storage B2 -key password -value 'mypwd'
```

Copy all snapshots to the new storage

```sh
duplicacy -log copy -to B2 -threads 10
```

Prune (run only from the NAS for both storages)

```sh
duplicacy -log prune -all -keep 0:1825 -keep 30:180 -keep 7:30 -keep 1:7
duplicacy -log prune -all -keep 0:1825 -keep 30:180 -keep 7:30 -keep 1:7 -storage B2
```

## Contribute

[![Contributor Covenant](https://img.shields.io/badge/Contributor%20Covenant-v2.0%20adopted-007ba7.svg)](https://www.contributor-covenant.org/version/2/0/code_of_conduct.html)

Contributions are always welcome! Please read the [contribution guidelines](.github/CONTRIBUTING.md) and the [code of conduct](.github/CODE_OF_CONDUCT.md).

## License
[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)

Licensed under the Apache License, Version 2.0.
See [LICENSE](LICENSE) file.
