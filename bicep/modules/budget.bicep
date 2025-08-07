@description('Name of the budget')
param BudgetName string

@description('Databricks Personal Access Token')
@secure()
param DatabricksToken string

@description('Databricks workspace URL')
param WorkspaceUrl string

@description('Budget configuration filter')
param Filter object

@description('Budget period configuration')
param Period object

@description('Budget start date (YYYY-MM-DD)')
param StartDate string

@description('Budget target amount')
param TargetAmount string

@description('Budget alerts configuration')
param Alerts array = []

var budgetConfig = {
  budget_configuration_id: BudgetName
  filter: Filter
  period: Period
  start_date: StartDate
  target_amount: TargetAmount
  alerts: Alerts
}

resource budgetCreation 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: 'create-databricks-budget-${uniqueString(BudgetName)}'
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
        name: 'BUDGET_CONFIG'
        value: string(budgetConfig)
      }
    ]
    scriptContent: '''
      $ErrorActionPreference = "Stop"
      
      # Convert secure token
      $secureToken = ConvertTo-SecureString $env:DATABRICKS_TOKEN -AsPlainText -Force
      
      # Create budget
      $createResponse = & "${PSScriptRoot}/../helpers/Invoke-DatabricksApi.ps1" `
        -Method "POST" `
        -UrlPath "/api/2.0/accounts/budgets" `
        -Body $env:BUDGET_CONFIG `
        -DatabricksToken $secureToken `
        -WorkspaceUrl $env:WORKSPACE_URL
      
      $budget = $createResponse | ConvertFrom-Json
      
      # Get budget details
      $budgetDetailsResponse = & "${PSScriptRoot}/../helpers/Invoke-DatabricksApi.ps1" `
        -Method "GET" `
        -UrlPath "/api/2.0/accounts/budgets/$($budget.budget_configuration_id)" `
        -DatabricksToken $secureToken `
        -WorkspaceUrl $env:WORKSPACE_URL
      
      $budgetDetails = $budgetDetailsResponse | ConvertFrom-Json
      
      $DeploymentScriptOutputs = @{
        budgetConfigurationId = $budgetDetails.budget_configuration_id
        budgetName = $budgetDetails.budget_configuration_id
        filter = ($budgetDetails.filter | ConvertTo-Json -Compress)
        period = ($budgetDetails.period | ConvertTo-Json -Compress)
        startDate = $budgetDetails.start_date
        targetAmount = $budgetDetails.target_amount
        alerts = ($budgetDetails.alerts | ConvertTo-Json -Compress)
        creationTime = $budgetDetails.creation_time
        updateTime = $budgetDetails.update_time
      }
    '''
  }
}

@description('The ID of the created budget')
output BudgetConfigurationId string = budgetCreation.properties.outputs.budgetConfigurationId

@description('The name of the budget')
output BudgetName string = budgetCreation.properties.outputs.budgetName

@description('The filter configuration of the budget')
output Filter string = budgetCreation.properties.outputs.filter

@description('The period configuration of the budget')
output Period string = budgetCreation.properties.outputs.period

@description('The start date of the budget')
output StartDate string = budgetCreation.properties.outputs.startDate

@description('The target amount of the budget')
output TargetAmount string = budgetCreation.properties.outputs.targetAmount

@description('The alerts configuration of the budget')
output Alerts string = budgetCreation.properties.outputs.alerts

@description('The creation time of the budget')
output CreationTime string = budgetCreation.properties.outputs.creationTime

@description('The last update time of the budget')
output UpdateTime string = budgetCreation.properties.outputs.updateTime
