param (
    # The name of the VSTS account
    [Parameter(Mandatory = $true)]
    [String]
    $vstsAccount,

    # The personal access token (PAT) used to authenticate with VSTS
    [Parameter(Mandatory = $true)]
    [String]
    $pat,

    # The Agent Pool
    [Parameter(Mandatory = $false)]
    [String]
    $agentPool = 'default'
)

# Create a group used to give access to the docker engine.
# See https://docs.microsoft.com/en-us/virtualization/windowscontainers/manage-docker/configure-docker-daemon#set-docker-security-group

$grp = New-LocalGroup -Name 'docker_engine' -Description 'Provides access to the Docker engine'

# Add the built-in Network Service account to this group.
# This is the account the vsts-agent will run under (by default)
Add-LocalGroupMember -Group $grp -Member 'NT AUTHORITY\NETWORKSERVICE'

# Now edit the Docker daemon.json config file.
$configFile = "$env:ProgramData\Docker\config\daemon.json"

# Get the current contents, if it exists
if(Test-Path -Path $configFile)
{
    $dconfig = Get-Content -Raw -Path "$env:ProgramData\Docker\config\daemon.json" | ConvertFrom-Json
}
else {
    $dconfig = New-Object -TypeName 'PSCustomObject'
}
# Add the "group" setting to the config.
$dconfig | Add-Member -MemberType NoteProperty -Name 'group' -Value 'docker_engine' -Force
# Write the config back to the file. Note this needs to be Ascii, otherwise Docker fails.
$dconfig | ConvertTo-Json -Depth 20 -Compress | Set-Content -Path $configFile -Encoding Ascii

# Now restart the docker engine. The vsts-agent will now have access to the Docker via the named pipe.
Restart-Service Docker

# Ensure we're using TLS 1.2, github now requires it.
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# Find out what the latest version of docker-compose is.
$dcrel = Invoke-RestMethod -Uri 'https://api.github.com/repos/docker/compose/releases/latest' `
            -UseBasicParsing -Headers @{ Accept = 'application/vnd.github.v3+json' }

$dcurl = ($dcrel.assets | ? name -EQ 'docker-compose-Windows-x86_64.exe').browser_download_url

# Now download and install docker-compose
Invoke-WebRequest $dcurl -UseBasicParsing -OutFile $Env:ProgramFiles\docker\docker-compose.exe

# Download the VSTS agent

# Get the url to the latest version of the agent.
$vstsAgentRel = Invoke-RestMethod -Uri 'https://api.github.com/repos/Microsoft/vsts-agent/releases/latest' `
               -UseBasicParsing -Headers @{ Accept = 'application/vnd.github.v3+json' }

# Downloads are listed in the assets.json
$assetsUrl = ($vstsAgentRel.assets | ? name -EQ 'assets.json').browser_download_url
$data = (Invoke-WebRequest -Uri $assetsUrl -UseBasicParsing).Content
$assets = [Text.Encoding]::UTF8.GetString($data) | ConvertFrom-Json
$vstsAgentUrl = ($assets | ? platform -EQ 'win-x64').downloadUrl

# Now download the agent
$vstsAgentZip = "$env:TEMP\$(($assets | ? platform -EQ 'win-x64').name)"
Invoke-WebRequest -Uri $vstsAgentUrl -UseBasicParsing -OutFile $vstsAgentZip

# Extract the ZIP file
Expand-Archive -Path $vstsAgentZip -DestinationPath "$env:SystemDrive\vsts-agent\"

# Tidy up
Remove-Item $vstsAgentZip

# Now set up the agent
Set-Location "$env:SystemDrive\vsts-agent\"
.\config.cmd --unattended --url "https://$($vstsAccount).visualstudio.com" --auth 'pat' --token $pat --pool $agentPool --agent "$env:COMPUTERNAME" --work 'D:\agent_work' --runAsService --acceptTeeEula
