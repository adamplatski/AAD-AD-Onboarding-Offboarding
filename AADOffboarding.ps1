<#
This script disables a terminated users access to their test.com account, revokes their AAD refresh-token,
and removes them from all azure groups and applications they have access to. It does this 1 day after their termination date.
The script indexes all bambooHR and Azure users like our other scripts but needs the BHR web-API to pull the terminationDate
field for employee's with upcoming termination dates. 
#>

$global:MakeChanges = $true

$MyCredential = "it-automation" 
$Body = "" 

$servicePrincipalConnection = Get-AutomationConnection -Name 'AzureRunAsConnection'        
Connect-AzureAD `
    -TenantId $servicePrincipalConnection.TenantId `
    -ApplicationId $servicePrincipalConnection.ApplicationId `
    -CertificateThumbprint $servicePrincipalConnection.CertificateThumbprint  

'Connected to Azure AD'

'Getting the Date'
$today = Get-Date -format s
     
# Get the PowerShell credential and prints its properties 
$Cred = Get-AutomationPSCredential -Name $MyCredential
if ($Cred -eq $null) { 
    Write-Output "Credential entered: $MyCredential does not exist in the automation service. Please create one `n"    
} 
else { 
    $CredUsername = $Cred.UserName 
    $CredPassword = $Cred.GetNetworkCredential().Password 
} 

"Getting Azure AD users"
$AadUsers = Get-AzureAdUser -All $True -Filter "usertype eq 'Member'"
    
"Indexing Azure AD users"
$AzureUsers = @{}
$Index = 0
foreach ($User in $AadUsers) {
    if ($User.Mail) {
        $AzureUsers[$User.Mail] = $Index
    }
    $Index++
}

'Getting BambooHR users'
$BambooUsersById = @{}
$BambooApiKey = Get-AutomationVariable -Name 'bamboohr_api_key'
$BambooDirectory = @(Get-BambooHRDirectory -Apikey $BambooApiKey -subDomain "test" `
        -fields "firstname,lastname,hiredate,terminationdate,workEmail,employmentHistoryStatus,supervisorEId,jobTitle,location,country,department,terminationDate")

"Indexing BambooHR users"
$BambooUsersById = @{}
$Index = 0
foreach ($BambooUser in $BambooDirectory) {
    $BambooUsersById[$BambooUser.id] = $Index
    $Index++
}


# Used to fetch individul employees
$Password = 'x' | ConvertTo-SecureString -AsPlainText -Force
$WebCred = New-Object -typename System.Management.Automation.PSCredential -Argumentlist $BambooApiKey, $Password
$Headers = @{'Accept' = 'application/json' }


"Getting BambooHR user termination dates`n"
foreach ($BambooUser in $BambooDirectory) {
    if ($BambooUser.terminationDate -eq "0000-00-00") {
        if ($BambooUser.hiredate -ne "0000-00-00") {
            $BambooUser.hireDate = [datetime]$BambooUser.hireDate         
            $URI = "https://api.bamboohr.com/api/gateway.php/test/v1/employees/{0}/?onlyCurrent=False&fields=terminationDate" -f $BambooUser.id        
            $Response = Invoke-WebRequest -Method 'GET' -Headers $Headers -Credential $WebCred -Uri $URI -UseBasicParsing | ConvertFrom-Json
            $BambooUser.terminationDate = $Response.terminationDate 
        }
    }
}


foreach ($BambooUser in $BambooDirectory) {
    
    if ($BambooUser.terminationDate -ne '0000-00-00') { 
        $BambooUser.terminationDate = [datetime]$BambooUser.terminationDate
        $lastDay = [datetime]$BambooUser.terminationDate         
        $adjdate = $lastDay.AddDays(+1) 
        $adjdate = $adjdate.ToString('yyyy-MM-dd')
        $Email = $BambooUser.workEmail
    
        if ($Email -ne $null) { 
            if ($AzureUsers.ContainsKey($Email)) {      
                $AdUser = $AadUsers[$AzureUsers[$Email]]    
                if ($BambooUser.hireDate -le $today) {
                    if ($today -ge $adjdate) {
                        $AADGroups = Get-AzureADUserMembership -ObjectId $AdUser.ObjectId | Where-Object ObjectType -eq 'Group'
                        "`n~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
                        "Offboarding $Email - termination date: $lastday "
                        "`nGetting group memberships " 
                        $EntApps = Get-AzureADUserAppRoleAssignment -ObjectId $AdUser.objectid | Where-Object { $_.PrincipalDisplayName -eq $AdUser.DisplayName }
                        "Getting application roles "
                        $Body += $BambooUser.workEmail + " had their application roles and refresh-token revoked, was removed from azure groups, and had their account disabled<br></br>"
                        if ($global:MakeChanges -eq $true) {
                            Set-AzureADUser -ObjectID $AdUser.ObjectId -AccountEnabled $false -ErrorAction SilentlyContinue
                            "`nBlocked account access "
                            Revoke-AzureADUserAllRefreshToken -ObjectId $AdUser.ObjectId -ErrorAction SilentlyContinue
                            "Revoked account Refresh-Tokens"
                            $EntApps | % { Get-AzureADUserAppRoleAssignment -ObjectId $AdUser.ObjectId } | Where-Object { $_.PrincipalDisplayName -eq $aduser.DisplayName } | % { Remove-AzureADUserAppRoleAssignment -ObjectId $_.PrincipalId -AppRoleAssignmentId $_.ObjectId } -ErrorAction SilentlyContinue
                            "Deleted application roles "
                            $EntApps  
                            "Removed user from all azure groups listed below:`n" 
                            foreach ($Group in $AADGroups) {   
                                $UsersGroups = $Group.DisplayName 
                                $UsersGroups           
                                Remove-AzureADGroupMember -ObjectId $Group.ObjectId -MemberId $AdUser.ObjectId -ErrorAction SilentlyContinue
                            }
                            "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
                        }
                    }
                }
            }
        }
    }
}
Send-MailMessage -To 'it-internal@test.com' -Subject "Terminated Employee Offboarding - Azure Removals and Disabling" -Body $Body -UseSsl -Port 587 -SmtpServer 'smtp.office365.com' -From 'it-automation@test.com' -BodyAsHtml -Credential $Cred