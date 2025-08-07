<#
.SYNOPSIS
Centralized helper for making Databricks REST API calls from Bicep modules.

.DESCRIPTION
This PowerShell script provides a single point for all Databricks API interactions,
handling authentication and providing consistent error handling across all Bicep modules.

.PARAMETER Method
HTTP method for the API call (GET, POST, PUT, DELETE, PATCH)

.PARAMETER UrlPath
The API endpoint path (e.g., "/api/2.1/clusters/create")

.PARAMETER Body
Optional JSON body for POST/PUT/PATCH requests

.PARAMETER DatabricksToken
Secure string containing the Databricks Personal Access Token

.PARAMETER WorkspaceUrl
The Databricks workspace URL (e.g., "https://adb-123456789.azuredatabricks.net")

.EXAMPLE
./Invoke-DatabricksApi.ps1 -Method "POST" -UrlPath "/api/2.1/clusters/create" -Body $clusterConfig -DatabricksToken $token -WorkspaceUrl $workspaceUrl
#>

param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("GET", "POST", "PUT", "DELETE", "PATCH")]
    [string]$Method,
    
    [Parameter(Mandatory = $true)]
    [string]$UrlPath,
    
    [Parameter(Mandatory = $false)]
    [string]$Body,
    
    [Parameter(Mandatory = $true)]
    [securestring]$DatabricksToken,
    
    [Parameter(Mandatory = $true)]
    [string]$WorkspaceUrl
)

try {
    $tokenPlainText = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($DatabricksToken))
    
    $headers = @{
        "Authorization" = "Bearer $tokenPlainText"
        "Content-Type" = "application/json"
    }
    
    $uri = "$WorkspaceUrl$UrlPath"
    
    $requestParams = @{
        Uri = $uri
        Method = $Method
        Headers = $headers
    }
    
    if ($Body -and ($Method -in @("POST", "PUT", "PATCH"))) {
        $requestParams.Body = $Body
    }
    
    Write-Host "Making $Method request to: $uri"
    
    $response = Invoke-RestMethod @requestParams
    
    return $response | ConvertTo-Json -Depth 10
}
catch {
    $errorMessage = "Databricks API call failed: $($_.Exception.Message)"
    if ($_.Exception.Response) {
        $statusCode = $_.Exception.Response.StatusCode
        $errorMessage += " (Status: $statusCode)"
        
        try {
            $errorBody = $_.Exception.Response.GetResponseStream()
            $reader = New-Object System.IO.StreamReader($errorBody)
            $responseText = $reader.ReadToEnd()
            $errorMessage += " Response: $responseText"
        }
        catch {
            $errorMessage += " (Could not read error response)"
        }
    }
    
    Write-Error $errorMessage
    throw $errorMessage
}
finally {
    if ($tokenPlainText) {
        $tokenPlainText = $null
    }
}
