$config = Get-Content ./config.json | ConvertFrom-Json
$Username = $config.defaults.username
$Password = $config.defaults.password
$URL = $config.defaults.baseurl
$debug = $config.defaults.debug
$subscriptions = $config.defaults.subscriptions
$directoryId = $config.defaults.directoryId
$applicationId = $config.defaults.applicationId
$authenticationKey = $config.defaults.authenticationKey

# TO BE REMOVED from "START HERE" to "END HERE" if you are using Powershell 6
# STARTS HERE
add-type @"
using System.Net;
using System.Security.Cryptography.X509Certificates;
public class TrustAllCertsPolicy : ICertificatePolicy {
    public bool CheckValidationResult(
        ServicePoint srvPoint, X509Certificate certificate,
        WebRequest request, int certificateProblem) {
        return true;
    }
}
"@
$AllProtocols = [System.Net.SecurityProtocolType]'Tls11,Tls12'
[System.Net.ServicePointManager]::SecurityProtocol = $AllProtocols
[System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy

# TO BE REMOVED 
# ENDS HERE

function getSubscriptions($subscriptions) {
	if (([IO.Path]::GetExtension($subscriptions)) -eq ".csv") {
		$file = Import-Csv -Path $subscriptions
		$file | ForEach-Object {
			$subscriptionName = (Get-AzSubscription -SubscriptionId $_.subscriptionId).Name
			AddConnector $_.subscriptionId $subscriptionName
		}
	}
	else {
		if ( $subscriptions -eq "all") {
			$subscriptions = $directoryId
		}
		$subscriptionId = Get-AzManagementGroup -GroupName $subscriptions -Expand -Recurse
		$i = 0
		While ($subscriptionId.Children[$i] -ne $null) {
			if ($subscriptionId.Children[$i].Type -eq "/subscriptions") {
				$subscriptionIds = $subscriptionId.Children[$i].Name
				$subscriptionName = (Get-AzSubscription -SubscriptionId $subscriptionIds).Name
				AddConnector $subscriptionIds $subscriptionName
				$i += 1
			}
			else {
				getSubscriptions $subscriptionId.Children[$i].Name
				$i += 1
			}
		}
	}
}

function main() {
	$subscriptionIds = @()
	
	if (($Username -eq $null) -OR ($Password -eq $null) -OR ($URL -eq $null) -OR ($subscriptions -eq $null) -OR ($directoryId -eq $null) -OR ($applicationId -eq $null) -OR ($authenticationKey -eq $null)) {
		write-host "Config information in ./config.json is not configured correctly. Exiting..."
		break
	}
	else {
		$URI = $URL + "/qps/rest/3.0/create/am/azureassetdataconnector"
		$base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(("{0}:{1}" -f $Username, $Password)))

		$Headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
		$headers.Add("X-Requested-With", "Qualys Runbook (Powershell)")
		$headers.Add("Accept", "application/json")
		$headers.Add("Content-Type", "application/json")
		$headers.Add("Authorization", ("Basic {0}" -f $base64AuthInfo))

		if ($debug -ne $null) {
			$debugfile = New-Item -itemType File -Name ("debug-" + $((Get-Date).tostring("dd-MM-yyyy-hh-mm-ss")) + ".log")
		}
		getSubscriptions $subscriptions
	}
}

function AddConnector($subscriptionIds, $subscriptionName) {
	echo "------------------------------Creating AZURE Connectors--------------------------------"
	Add-Content "------------------------------Creating AZURE Connectors--------------------------------" -Path $debugfile.Name
	$bodycontent = @"
{
"ServiceRequest": {
        "data": {
            "AzureAssetDataConnector": {
                "name": "$($subscriptionName)",
                "description": "Azure connector created using API",
               
                
                "disabled": false,
                "runFrequency": 240,
                "isRemediationEnabled": true,
                "isGovCloudConfigured": false,
                "authRecord": {
                    "applicationId": "$($applicationId)",
                    "directoryId": "$($directoryId)",
                    "subscriptionId": "$($subscriptionIds)",
                    "authenticationKey": "$($authenticationKey)"
                },
                "connectorAppInfos": {
                    "set": {
                        "ConnectorAppInfoQList": [
                            {
                                "set": {
                                    "ConnectorAppInfo": {
                                        "name": "AI",
                                        "identifier": "$($subscriptionIds)"
                                       
                                    }
                                }
                            },
                            {
                                "set": {
                                    "ConnectorAppInfo": {
                                        "name": "CI",
                                        "identifier": "$($subscriptionIds)"
                                    }
                                }
                            },
                            {
                                "set": {
                                    "ConnectorAppInfo": {
                                        "name": "CSA",
                                        "identifier": "$($subscriptionIds)"
                                    }
                                }
                            }
                        ]
                    }
                }
            }
        }
    }
}
"@
		
	try {
		echo "Connector with below details is being created"
		echo $bodycontent
		Add-Content "Connector with below details" -Path $debugfile.Name
		Add-Content $body -Path $debugfile.Name
		$result = Invoke-WebRequest -Headers $headers -Uri $URI -Method Post -Body $bodycontent   
		Write-Host "StatusCode" $result.StatusCode
		if ($debug -ne $null) {
			Add-Content  -Path $debugfile.Name "is created Successfully"
			Add-Content  -Path $debugfile.Name $result.content
			Add-Content  -Path $debugfile.Name "-------------------------------------------------------------------------"
		}
	}
	catch {
		Write-Host "StatusCode:" $_.Exception.Response.StatusCode.value__ 
		Write-Host "StatusDescription:" $_.Exception.Response.StatusDescription
		if ($debug -ne $null) {
			Add-Content  -Path $debugfile.Name "is not created Successfully"
			Add-Content  -Path $debugfile.Name $_.Exception
			Add-Content  -Path $debugfile.Name "-------------------------------------------------------------------------"
		}
	}
}		
main
