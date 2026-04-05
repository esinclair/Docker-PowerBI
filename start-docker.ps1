# Docker run script for Power BI Report Server
param(
    [string]$SaPassword    = "yesPl3ase",
    [string]$PbirsUser     = "PBIAdmin",
    [string]$PbirsPassword = "yesPl3ase",
    [string]$HostVolume    = "C:/temp2/",
    [string]$ContainerVolume = "C:/temp/",
    [string]$Memory        = "6048mb",
    [string]$Image         = "healisticengineer/pbirs1.14:latest",
    [int]$SqlPort          = 1433,
    [int]$WebPort          = 80
)

docker run -d `
    -p "${SqlPort}:1433" `
    -p "${WebPort}:80" `
    -v "${HostVolume}:${ContainerVolume}" `
    -e "sa_password=$SaPassword" `
    -e "ACCEPT_EULA=Y" `
    -e "pbirs_user=$PbirsUser" `
    -e "pbirs_password=$PbirsPassword" `
    --memory $Memory `
    $Image
