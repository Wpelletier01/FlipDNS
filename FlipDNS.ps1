#Requires -RunAsAdministrator

# Argument possible a passer au script
[CmdletBinding()] # si vous passer un mauvais argument, une erreur vous sera rapporter
param(
    [switch]$quiet = $false,
    [switch]$test = $false ,
    [switch]$reset = $false,
    [switch]$flush = $false,
    [switch]$force = $false
)


# CONSTANTE
$IPV4 = 2 # C'est la valeur utilisé pour représenter un adresse IPV4
$SAVE = "C:\Program Files\FlipDNS\data\save.csv"
$HEADER = "name;type;current;original;last_change"
$DOMAIN_NAME_TEST = "google.com"
$IPV4_REGEX = "^(\b25[0-5]|\b2[0-4][0-9]|\b[01]?[0-9][0-9]?)(\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)){3}"
$ESC=[char]27
$TMP_FILE =  "C:\Program Files\FlipDNS\data\output.txt"

class InterfaceInfo {
    <#
    .DESCRIPTION
    Instance qui encapsule tout les informations pertinentes sur une interface se retrouvant dans
    un fichier de sauvegarde
    #>
    [string]$name
    [uint16]$type
    [ipaddress[]]$current 
    [ipaddress[]]$original
    [string]$last_change

    InterfaceInfo(
        [string]$n,
        [uint16]$t,
        [ipaddress[]]$c,
        [ipaddress[]]$o,
        [string]$l 
    ) {
        <#
        .DESCRIPTION
        Constructeur par défaut de cette classe. Il devrais être utiliser pour quand abriter les information
        qui ont ete chercher dans la sauvegarde.
        .PARAMETER n
        Nom de l'interface
        .PARAMETER t 
        Type de l'interface (4 ou 5)
        .PARAMETER $c
        L'adresse(s) du dns qui sont utiliser dans la configuration présente de l'interface
        .PARAMETER $o
        L'adresse(s) du dns qui était configurer au depart sur l'interface
        .PARAMETER $l
        l’étampe de temps représentent la dernière modification de la configuration dns
        #>

        $this.name = $n
        $this.type = $t 
        $this.current = $c
        $this.original = $o
        $this.last_change = $l

    }

    InterfaceInfo(
        [string]$n,
        [uint16]$t,
        [ipaddress[]]$c
    ) {
        <#
        .DESCRIPTION
        Constructeur secondaire de cette classe. Il devrais être utiliser pour quand abriter de l'information
        de nouvelle interface.
        .PARAMETER n
        Nom de l'interface
        .PARAMETER t 
        Type de l'interface (4 ou 5)
        .PARAMETER $c
        L'adresse(s) du dns qui sont utiliser dans la configuration présente de l'interface
        #>


        $this.name = $n
        $this.type = $t 
        $this.current = $c
        $this.original = $c # la configuration présente seras l'original
        $this.last_change = Get-Date -Format "yy-MM-dd HH:mm:ss"
    }

    InterfaceInfo() {}

    [string]ToRow() {
        <#
        .DESCRIPTION
        Formate tous les informations de cette instance sous forme de ranger respectant le
        formatage du fichier de sauvegarde
        #>
        return ( '{0};{1};{2};{3};{4}' -f
            $this.name,$this.type,($this.current -join ','),($this.original -join ','),$this.last_change)
    }

    [void]change_current_ips([ipaddress[]]$ips) {
        <#
        .DESCRIPTION 
        Remplace l'adresses(s) qui est enregistrer dans cette instance et 
        met a jour la date et l'heure du dernier changement.

        .PARAMETER ips 
        L'adresse(s) ip du serveur DNS
        #>

        $this.current = $ips
        $this.last_change = Get-Date -Format "yy-MM-dd HH:mm:ss"
        
    }

}

#################################################
#
#       Utilitaire
#
#################################################


function Test-Name-Resolving {
    param(
        [InterfaceInfo[]]$interface 
    )

    info! ("Test de Resolution Interface: {0}" -f $interface.name)

    foreach($ip in $interface.current) {
     
        try {
            Resolve-DnsName -Name $DOMAIN_NAME_TEST -Server $ip -QuickTimeout -ErrorAction Stop | Out-Null
            info! ("Resolution du domaine {0} au serveur {1}: valide" -f $DOMAIN_NAME_TEST,$ip)
            
            info! ("Interface: {0} configuration valide" -f $interface.name)
            # si au moins une resolution march c'est un succès
            return $true


        } catch {

            warn! ("Resolution du domaine {0} au serveur {1}: invalide" -f $DOMAIN_NAME_TEST,$ip) 
           
        } 

    }

    return $false
}

function Show-Menu {
    param (
       [InterfaceInfo]$interface
    )

    <#
    .DESCRIPTION
    Affiche au terminal un interface tui permettant au utilisateur de choisir de nouvelle adresse dns 
    pour leur configuration.
    
    .PARAMETER interface
    L'interface a modifier sa configuration dns
    
    #>

    # Vous laisser le temps de lire les log
    Start-Sleep -Seconds 1

    # Afficher une bar de progression de 3 secondes
    for ($i=0;$i -lt 3;$i++) {
        Write-Progress -Activity "Démarrage de FlipDNS-menu" -SecondsRemaining (3 - $i) -Status "Temp restant:"
        Start-Sleep -Seconds 1
    }
    
    # Affiche le menu
    # 1. l'utilisateur choisi et confirme de nouvelle adresse(s)
    # 2. Le programme écrit sont choix dans un fichier temporaire
    flipdns-menu.exe --interface $interface.name --ip-version $interface.type

    # C'est passer sans problème 
    if ($LastExitCode -eq 0) {
        info! ("Nouvelle adresse sélectionner pour l'interface '{0}'" -f $interface.name)
    
    # L'utilisateur a appuyer sur échappe dans le menu
    } elseif ($LastExitCode -eq 200) {
        warn! "vous avez quitter prématurément du menu. Config non modifier"
    }

}

function Get-Ipv4 {
    <#
    .DESCRIPTION 
    Génère une adresse IPV4 aléatoire 
    .OUTPUTS 
    L'adresse généré
    #>

    # choisi le premier octet
    $ip=[string](Get-Random -Maximum 255)

    # choisi les 3 prochains octets
    for($i=0;$i -lt 3; $i++) {
        $ip= ("{0}.{1}" -f $ip,(Get-Random -Maximum 255))
    }
    
    return $ip
}

function Convert-String-To-IpAddresses {
    param (
        [string]$data
    )
    <#
    .DESCRIPTION
    Converti une chaîne de caractère en une liste d’adresse ip
    .PARAMETER data
    La chaîne de caractère a convertir
    .OUTPUTS 
    Un liste d'adresse ip
    #>

    [System.Collections.ArrayList]$ips = @()
    # couper en morceau la chaîne  l'aide de la virgule et garder seulement ce qui n'est pas vide ou null
    foreach($ip in ($data.Split(',') | Where-Object { $_ } | Sort-Object -uniq)) {
        # S'il échoue, la config à ete modifier et devra être refaite
        
        if (-not ($ip -match $IPV4_REGEX)) {
            fatal! ("l'adresse ip {0} est invalide, générer une nouvelle sauvegarde" -f $ip)
        }

        $ips.Add($ip) | Out-Null
    }

    return $ips

}

#################################################
#
#       Fichier de configuration
#
#################################################

function New-Base-Save {
    <#
    .DESCRIPTION
    Génère le dossier et le fichier de sauvegarde
    #>

    New-Item data -ItemType Directory -ErrorAction Ignore | Out-Null
    
    New-Item $SAVE -ItemType File  -ErrorAction Ignore | Out-Null
    # ajoute les noms des colonnes
    Set-Content $SAVE $HEADER

}

function Read-Save {
    <#
    .DESCRIPTION 
    Va chercher le contenu des sauvegardes
    .OUTPUTS 
    Une liste d'instance InterfaceInfo
    #>

    $entries=[System.Collections.ArrayList]::new()

    # Si le fichier n'existe pas on retourne rien
    if ((Test-Path -Path $SAVE) -eq $false) {
        return $entries
    }

    # lit la sauvegarde en prenant compte que c'est un fichier csv
    $data=(Import-Csv -Path $SAVE -Delimiter ';')

    foreach($entry in $data) {
        
        # s'assure que la date de la dernière sauvegarde est valide
        try {
            [DateTime]::ParseExact($entry.last_change, "yy-MM-dd HH:mm:ss", [System.Globalization.CultureInfo]::InvariantCulture) | Out-Null
        } catch {
        
            fatal! ("Sauvegarde Corrompus Mauvaise Date: {0}. Générer une nouvelle sauvegarde" -f $entry.last_change)
    
        }
        
        # S'assure que le type est valide
        if (@(4,6) -notcontains $entry.type) {
            fatal! ("Sauvegarde Corrompus Mauvais type: {0}. Générer une nouvelle sauvegarde" -f $entry.type)
        }


        $info = [InterfaceInfo]::new(
            $entry.name, 
            $entry.type,
            (Convert-String-To-IpAddresses $entry.current),
            (Convert-String-To-IpAddresses $entry.original),
            $entry.last_change 
        )
        
        
        # Quand on ajoute a une liste, son index est retourner au terminal
        # et on ne veut pas ca
        $entries.Add($info) | Out-Null

    }

    return $entries
    
}

function Write-Save {
    param(
        [InterfaceInfo]$interface
    )
    <#
    .DESCRIPTION 
    Ajoute une interface et c'est info dans le fichier de sauvegarde
    .PARAMETER interface
    l’interface a ajouter
    #>

    Add-Content -Path $SAVE -Value $interface.ToRow()
}

function Update-Save {
    param(
        [InterfaceInfo[]]$interfaces
    )
    <#
    .DESCRIPTION 
    Efface et met a jour le fichier de sauvegarde
    .PARAMETER interface
    Les interfaces a mettre dans le fichier de sauvegarde
    #>

    # Efface tout
    Clear-Save
    # Ajoute les nouvelles informations
    $interfaces.ForEach({ Write-Save $_ })
}

function Clear-Save {
    <#
    .DESCRIPTION 
    Efface tout les entrer dans le fichier de config
    #>

    Clear-Content -Path $SAVE -ErrorAction Ignore
    # on veut garder les noms des colonnes
    Add-Content -Path $SAVE -Value $HEADER

}

function Get-Current-Interface-Info {
    <#
    .DESCRIPTION
    Va chercher les informations sur les interface de reseau active
    .OUTPUTS 
    Une liste d'instance InterfaceInfo
    #>
    
    $interfaces= [System.Collections.ArrayList]@()

    # On va chercher Tous les interface reseau physique
    foreach ($adapt in (Get-NetAdapter -Name * -Physical) ) {
        # on veut que ceux active
        if ($adapt.Status -eq "up") {

            $name=$adapt.Name 

            foreach($dnsclient in (Get-DnsClientServerAddress -InterfaceAlias $name)){
                # On veut juste les address IPV4
                if ($dnsclient.SystemName -eq $IPV4) {
                    # S'il a au moins une adresse de Serveur DNS, on l'ajoute(s) ou on ajoute une liste vide
                    if ($dnsclient.ServerAddresses -gt 0) {
                        $interfaces.Add([InterfaceInfo]::new($name,4,$dnsclient.ServerAddresses)) | Out-Null
                    } else {
                        $interfaces.Add([InterfaceInfo]::new($name,4,@())) | Out-Null
                    }
                
                } 

            }
        }        
    }

    return $interfaces        
}

#################################################
#
#       Logging
#
#################################################

function Log {
    <#
    .DESCRIPTION
    Entre un log dans l'observateur d’événement
    
    .PARAMETER type
    le type de log 

    .PARAMETER message
    le contenu du log
    
    #>
    param (
        $type,
        $message
    )

    # pour incrémenter l'id de l’événement 
    $eid=(Get-EventLog -LogName "FlipDNS" -Source "FlipDNS" | Measure-Object).Count + 1
    # Ajoute le log au observateur d’événement
    Write-EventLog -LogName "FlipDNS" -Source "FlipDNS" -EventId $eid -EntryType $type -Message $message
        
}

function trace! {
    <#
    .DESCRIPTION
    Entre un log de type Trace sur le terminal 
    si l'option quiet n'est pas specifier.
    
    .PARAMETER message
    la description du log
    
    #>
    param (
        [string]$message
    )
    
    # log seulement si quiet n'est pas activé
    if ($quiet -eq $false) {
        Write-Host ("[$ESC[94mTRACE$ESC[0m] {0}" -f $message)
    }
}

function info! {
    <#
    .DESCRIPTION
    Entre un log de type Info dans l'observateur d’événement et sur le terminal 
    si l'option quiet n'est pas specifier.
    
    .PARAMETER message
    la description du log
    
    #>
    param (
        [string]$message
    )

    # Ajoute le message au observateur d’événement
    Log ([System.Diagnostics.EventLogEntryType]::Information) $message
    
    # log seulement si quiet n'est pas activé
    if ($quiet -eq $false) {
        Write-Host ("[$ESC[92mINFO$ESC[0m] {0}" -f $message)
    }
}

function warn! {
    <#
    .DESCRIPTION
    Entre un log de type Avertissement dans l'observateur d’événement et sur le terminal 
    si l'option quiet n'est pas specifier
    
    .PARAMETER message
    la description du log
    
    #>
    param (
        [string]$message
    )

    # Ajoute le message au observateur d’événement
    Log ([System.Diagnostics.EventLogEntryType]::Warning) $message

    # log seulement si quiet n'est pas activé
    if ($quiet -eq $false) {
        Write-Host ("[$ESC[93mAVERTISSEMENT$ESC[0m] {0}" -f $message)
    }
    
}

function error! {
    <#
    .DESCRIPTION
    Entre un log de type Erreur dans l'observateur d’événement et sur le terminal 
    si l'option quiet n'est pas specifier
    
    .PARAMETER message
    la description du log
    
    #>
    
    param (
        [string]$message
    )

    # Ajoute le message au observateur d’événement
    Log ([System.Diagnostics.EventLogEntryType]::Error) $message
    
    # log seulement si quiet n'est pas activé
    if ($quiet -eq $false) {
        Write-Host ("[$ESC[91mERREUR$ESC[0m] {0}" -f $message)
    }
}

function fatal! {
    <#
    .DESCRIPTION
    Entre un log de type Fatal dans l'observateur d’événement et sur le terminal 
    si l'option quiet n'est pas specifier
    
    .PARAMETER message
    la description du log
    
    #>
    param (
        [string]$message
    )

    # Ajoute le message au observateur d’événement
    Log ([System.Diagnostics.EventLogEntryType]::Error) $message

    # log seulement si quiet n'est pas activé
    if ($quiet -eq $false) {
        Write-Host ("[$ESC[91mFATAL$ESC[0m] {0}" -f $message)
    }

    exit(200)
}

#################################################
#
#                   SCRIPT
#
#################################################


# Verification de base

# regarde si la source pour FlipDNS existe
if(![System.Diagnostics.EventLog]::SourceExists("FlipDNS")) {
    Write-Host -ForegroundColor Red "Incapable d’écrire dans l'observateur d’événement."
    Write-Host -ForegroundColor Red "Veuillez réinstaller le programme."

    exit(1)
}

# regarde ce qui a ete passer en argument 
if (($PSBoundParameters.Count -gt 2) -or (($quiet -eq $false ) -and ($PSBoundParameters.Count -eq 2) )) {

    fatal! "Le script peut que prendre un argument la fois quiet + un autre"

# pour aucun argument ou seulement quiet a ete specifier
} elseif (($PSBoundParameters.Count -eq 1 -and $quiet -eq $true) -or ($PSBoundParameters.Count -eq 0)) {

    # On va lire la sauvegarde.
    $data=(Read-Save)

    # Si celle-ci est vide, on va en générer une
    if ($data.Count -eq 0) {

        info! "Mémoire vide, extraction des données des interface reseau sera executer"

        # régénère le fichier de sauvegarde de base
        New-Base-Save

        # Va récolter les informations sur les cartes reseaux
        $entries=(Get-Current-Interface-Info)

        # ajoute les informations collecter dans le fichier de sauvegarde
        Update-Save $entry

        info! "Collecte et sauvegarde des information sur les interfaces reseaux"

        $data=$entries

    } 
 
    foreach($int in $data) {

        if ( !(Test-Name-Resolving $int) ) {

            error! ("La configuration de l'interface {0} est invalide" -f $int.name)

            trace! "le menu de selection commencera sous-peu"
            
            # On fait apparaître le menu de selection
            Show-Menu $int

            # Récolte les nouvelles adresse de Serveur DNS choisi
            $dns = (Get-Content $TMP_FILE).Split(" ")

            info! ("Nouvelle adresse: {0}" -f [string]$dns -join " ")
            
            # On change l'adresse(s) DNS de la carte reseau
            Set-DnsClientServerAddress -InterfaceAlias $int.name -ServerAddresses  $dns

            # Met a jour les info dns et le temps ou le changement a ete fait
            $int.change_current_ips($dns)

        } 

    }

   
    # Met les info a jour dans le fichier de sauvegarde
    Update-Save $data

# Pour tout les autre argument possible    
} else {
    # Passer l'argument -reset
    if ( $reset -eq $true) {
        
        # Lit la sauvegarde
        $data=(Read-Save)

        if ($data.Count -eq 0) {
            fatal! "Essaie de reset sans entrer. Executer FlipDNS.ps1 en premier"
        }

        # Remplace la valeur DNS presente par la valeur original 
        foreach($interface in $data) {

            Set-DnsClientServerAddress -InterfaceAlias $interface.name -ServerAddresses  $interface.original
            info! ("Version original de l'interface {0} a ete apliquer" -f $interface.name)
            
            $interface.change_current_ips($interface.original)

        }

        # Met les info a jour dans le fichier de sauvegarde
        Update-Save $data

        info! "Le fichier de sauvegarde a ete mis a jour"

    } elseif ( $test -eq $true ) {

        $ints = (Read-Save)

        # On ne peut pas tester des valeur aléatoire si la sauvegarde est vide
        if($ints.Count -eq 0) {
            fatal! "Vous ne pouvez pas effectuer une execution en mode test si vous n'avez pas des interfaces deja sauvegarder"
        }

        foreach($int in $ints) {

            # génère un adresse IPV4 aléatoire
            $rand_ip=(Get-Ipv4) 
            # change les paramètre DNS avec l'adresse aléatoire
            Set-DnsClientServerAddress -InterfaceAlias $int.name -ServerAddresses (Get-Ipv4) 
    
            $int.change_current_ips(@($rand_ip))

            info! ("Interface {0} a ete configurer avec les adresse {1}" -f $int.name, $rand_ip)
            
        }

        Update-Save $ints 


    } elseif ( $flush -eq $true) {

        # Efface la sauvegarde
        Clear-Save
        info! "les sauvegarde on ete effacer avec succès"
        
    } elseif ( $force -eq $true) {

        # Récolte info dans sauvegarde
        $interfaces=(Read-Save)

        # 
        if ($interfaces.Count -eq 0) {
            fatal! "Vous devez ne pouvez pas executer en mode forcer si vous n'avez pas deja une sauvegarde présente"
        }

        foreach($int in $interfaces) {

            # Affiche le menu sans exception le menu de choix
            trace! "le menu de selection commencera sous-peu"
            Show-Menu $int
            # Va chercher les valeurs choisi dans le menu
            $dns = (Get-Content $TMP_FILE)
            
            if ($null -ne $dns) {
            
                info! ("Nouvelle adresse: {0}" -f [string]$dns -join " ")

                $dns = $dns.Split(" ")
                # change les paramètre DNS
                Set-DnsClientServerAddress -InterfaceAlias $int.name -ServerAddresses  $dns
                # Efface la valeur choisi pour le prochain
                Clear-Content  $TMP_FILE
                # met a jour le temp de la dernière modification
                $int.change_current_ips($dns)
            }

        }
        # Met a jour la sauvegarde 
        Update-Save $interfaces

    }
    
}