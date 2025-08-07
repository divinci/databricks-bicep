@description('Name of the external location')
param LocationName string

@description('Databricks Personal Access Token')
@secure()
param DatabricksToken string

@description('Databricks workspace URL')
param WorkspaceUrl string

@description('URL of the external location')
param Url string

@description('Storage credential name')
param CredentialName string

@description('Comment for the external location')
param Comment string = ''

@description('Owner of the external location')
param Owner string = ''

@description('Whether the location is read-only')
param ReadOnly bool = false

@description('Whether to skip validation')
param SkipValidation bool = false

var locationConfig = {
  name: LocationName
  url: Url
  credential_name: CredentialName
  comment: empty(Comment) ? null : Comment
  owner: empty(Owner) ? null : Owner
  read_only: ReadOnly
  skip_validation: SkipValidation
}

resource externalLocationCreation 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: 'create-databricks-external-location-${uniqueString(LocationName)}'
  location: resourceGroup().location
  kind: 'AzurePowerShell'
  properties: {
    azPowerShellVersion: '9.0'
    timeout: 'PT30M'
    retentionInterval: 'PT1H'
    environmentVariables: [
      {
        name: 'DATABRICKS_TOKEN'
        secureValue: DatabricksToken
      }
      {
        name: 'WORKSPACE_URL'
        value: WorkspaceUrl
      }
      {
        name: 'LOCATION_CONFIG'
        value: string(locationConfig)
      }
    ]
    scriptContent: '''
      $ErrorActionPreference = "Stop"
      
      # Convert secure token
      $secureToken = ConvertTo-SecureString $env:DATABRICKS_TOKEN -AsPlainText -Force
      
      # Create external location
      $createResponse = & "${PSScriptRoot}/../helpers/Invoke-DatabricksApi.ps1" `
        -Method "POST" `
        -UrlPath "/api/2.1/unity-catalog/external-locations" `
        -Body $env:LOCATION_CONFIG `
        -DatabricksToken $secureToken `
        -WorkspaceUrl $env:WORKSPACE_URL
      
      $location = $createResponse | ConvertFrom-Json
      
      # Get location details
      $locationDetailsResponse = & "${PSScriptRoot}/../helpers/Invoke-DatabricksApi.ps1" `
        -Method "GET" `
        -UrlPath "/api/2.1/unity-catalog/external-locations/$($location.name)" `
        -DatabricksToken $secureToken `
        -WorkspaceUrl $env:WORKSPACE_URL
      
      $locationDetails = $locationDetailsResponse | ConvertFrom-Json
      
      $DeploymentScriptOutputs = @{
        locationName = $locationDetails.name
        url = $locationDetails.url
        credentialName = $locationDetails.credential_name
        owner = $locationDetails.owner
        comment = $locationDetails.comment
        readOnly = $locationDetails.read_only
        createdAt = $locationDetails.created_at
        updatedAt = $locationDetails.updated_at
      }
    '''
  }
}

@description('The name of the created external location')
output LocationName string = externalLocationCreation.properties.outputs.locationName

@description('The URL of the external location')
output Url string = externalLocationCreation.properties.outputs.url

@description('The storage credential name')
output CredentialName string = externalLocationCreation.properties.outputs.credentialName

@description('The owner of the external location')
output Owner string = externalLocationCreation.properties.outputs.owner

@description('The comment for the external location')
output Comment string = externalLocationCreation.properties.outputs.comment

@description('Whether the location is read-only')
output ReadOnly bool = bool(externalLocationCreation.properties.outputs.readOnly)

@description('The creation timestamp of the external location')
output CreatedAt int = int(externalLocationCreation.properties.outputs.createdAt)

@description('The last updated timestamp of the external location')
output UpdatedAt int = int(externalLocationCreation.properties.outputs.updatedAt)
