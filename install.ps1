#Requires -RunAsAdministrator

[CmdletBinding()] # si vous passer un mauvais argument, une erreur vous sera rapporter
param(
    [switch]$build = $false
)

# nous permettre d'executer des script
Set-ExecutionPolicy RemoteSigned

# Créer la base du dossier ou le script résidera
New-Item "C:\Program Files\FlipDNS" -ItemType Directory -ErrorAction Ignore | Out-Null
New-Item "C:\Program Files\FlipDNS\data" -ItemType Directory -ErrorAction Ignore | Out-Null

if ($build) {

    $current=(Get-Location)

    Set-Location -Path ("{0}/flipdns-menu" -f $current)

    cargo build --release  
    
    Copy-Item -Path ("{0}/bin/release/flipdns-menu.exe" -f $current) -Destination ("{0}/exec/flipdns-menu.exe" -f $current)

    Set-Location -Path $current
}

# ajout le dossier flipdns dans la variable PATH
$Path = [Environment]::GetEnvironmentVariable("PATH", "Machine") + [IO.Path]::PathSeparator + "C:\Program Files\FlipDNS"
[Environment]::SetEnvironmentVariable( "Path", $Path, "Machine" )


# Copie les executables
Copy-Item -Path ".\exec\flipdns-menu.exe" -Destination  "C:\Program Files\FlipDNS\flipdns-menu.exe"
Copy-Item -Path ".\FlipDNS.ps1" -Destination "C:\Program Files\FlipDNS\FlipDNS.ps1"

# créer logname et source
if(-not([System.Diagnostics.EventLog]::Exists("FlipDNS"))) {
    New-EventLog -LogName FlipDNS -Source FlipDNS
}
