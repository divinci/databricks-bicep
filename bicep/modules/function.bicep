@description('Name of the Unity Catalog function')
param FunctionName string

@description('Catalog name for the function')
param CatalogName string

@description('Schema name for the function')
param SchemaName string

@description('Databricks Personal Access Token')
@secure()
param DatabricksToken string

@description('Databricks workspace URL')
param WorkspaceUrl string

@description('Input parameters for the function')
param InputParams array

@description('Data type of the function return value')
param DataType string

@description('Full data type specification')
param FullDataType string

@description('Return parameters for the function')
param ReturnParams object = {}

@description('Routine body for the function')
param RoutineBody string

@description('Routine definition for the function')
param RoutineDefinition string

@description('Routine dependencies for the function')
param RoutineDependencies array = []

@description('Parameter style for the function')
@allowed(['S', 'SQL'])
param ParameterStyle string = 'S'

@description('Whether the function is deterministic')
param IsDeterministic bool = true

@description('SQL data access for the function')
@allowed(['CONTAINS_SQL', 'READS_SQL_DATA', 'MODIFIES_SQL_DATA', 'NO_SQL'])
param SqlDataAccess string = 'CONTAINS_SQL'

@description('Whether the function is null call')
param IsNullCall bool = false

@description('Security type for the function')
@allowed(['DEFINER'])
param SecurityType string = 'DEFINER'

@description('Specific name for the function')
param SpecificName string = ''

@description('Comment for the function')
param Comment string = ''

@description('Owner of the function')
param Owner string = ''

@description('Properties for the function')
param Properties object = {}

var functionConfig = {
  name: FunctionName
  catalog_name: CatalogName
  schema_name: SchemaName
  input_params: InputParams
  data_type: DataType
  full_data_type: FullDataType
  return_params: empty(ReturnParams) ? null : ReturnParams
  routine_body: RoutineBody
  routine_definition: RoutineDefinition
  routine_dependencies: RoutineDependencies
  parameter_style: ParameterStyle
  is_deterministic: IsDeterministic
  sql_data_access: SqlDataAccess
  is_null_call: IsNullCall
  security_type: SecurityType
  specific_name: empty(SpecificName) ? null : SpecificName
  comment: empty(Comment) ? null : Comment
  owner: empty(Owner) ? null : Owner
  properties: empty(Properties) ? {} : Properties
}

resource functionCreation 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: 'create-databricks-function-${uniqueString(FunctionName)}'
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
        name: 'FUNCTION_CONFIG'
        value: string(functionConfig)
      }
    ]
    scriptContent: '''
      $ErrorActionPreference = "Stop"
      
      # Convert secure token
      $secureToken = ConvertTo-SecureString $env:DATABRICKS_TOKEN -AsPlainText -Force
      
      # Create Unity Catalog function
      $createResponse = & "${PSScriptRoot}/../helpers/Invoke-DatabricksApi.ps1" `
        -Method "POST" `
        -UrlPath "/api/2.1/unity-catalog/functions" `
        -Body $env:FUNCTION_CONFIG `
        -DatabricksToken $secureToken `
        -WorkspaceUrl $env:WORKSPACE_URL
      
      $function = $createResponse | ConvertFrom-Json
      
      # Get function details
      $functionDetailsResponse = & "${PSScriptRoot}/../helpers/Invoke-DatabricksApi.ps1" `
        -Method "GET" `
        -UrlPath "/api/2.1/unity-catalog/functions/$($function.full_name)" `
        -DatabricksToken $secureToken `
        -WorkspaceUrl $env:WORKSPACE_URL
      
      $functionDetails = $functionDetailsResponse | ConvertFrom-Json
      
      $DeploymentScriptOutputs = @{
        functionName = $functionDetails.name
        catalogName = $functionDetails.catalog_name
        schemaName = $functionDetails.schema_name
        fullName = $functionDetails.full_name
        dataType = $functionDetails.data_type
        fullDataType = $functionDetails.full_data_type
        routineBody = $functionDetails.routine_body
        routineDefinition = $functionDetails.routine_definition
        parameterStyle = $functionDetails.parameter_style
        isDeterministic = $functionDetails.is_deterministic
        sqlDataAccess = $functionDetails.sql_data_access
        isNullCall = $functionDetails.is_null_call
        securityType = $functionDetails.security_type
        specificName = $functionDetails.specific_name
        comment = $functionDetails.comment
        owner = $functionDetails.owner
        createdAt = $functionDetails.created_at
        updatedAt = $functionDetails.updated_at
        functionId = $functionDetails.function_id
      }
    '''
  }
}

@description('The name of the created function')
output FunctionName string = functionCreation.properties.outputs.functionName

@description('The catalog name of the function')
output CatalogName string = functionCreation.properties.outputs.catalogName

@description('The schema name of the function')
output SchemaName string = functionCreation.properties.outputs.schemaName

@description('The full name of the function')
output FullName string = functionCreation.properties.outputs.fullName

@description('The data type of the function')
output DataType string = functionCreation.properties.outputs.dataType

@description('The full data type specification')
output FullDataType string = functionCreation.properties.outputs.fullDataType

@description('The routine body of the function')
output RoutineBody string = functionCreation.properties.outputs.routineBody

@description('The routine definition of the function')
output RoutineDefinition string = functionCreation.properties.outputs.routineDefinition

@description('The parameter style of the function')
output ParameterStyle string = functionCreation.properties.outputs.parameterStyle

@description('Whether the function is deterministic')
output IsDeterministic bool = bool(functionCreation.properties.outputs.isDeterministic)

@description('The SQL data access of the function')
output SqlDataAccess string = functionCreation.properties.outputs.sqlDataAccess

@description('Whether the function is null call')
output IsNullCall bool = bool(functionCreation.properties.outputs.isNullCall)

@description('The security type of the function')
output SecurityType string = functionCreation.properties.outputs.securityType

@description('The specific name of the function')
output SpecificName string = functionCreation.properties.outputs.specificName

@description('The comment for the function')
output Comment string = functionCreation.properties.outputs.comment

@description('The owner of the function')
output Owner string = functionCreation.properties.outputs.owner

@description('The creation timestamp of the function')
output CreatedAt int = int(functionCreation.properties.outputs.createdAt)

@description('The last updated timestamp of the function')
output UpdatedAt int = int(functionCreation.properties.outputs.updatedAt)

@description('The unique ID of the function')
output FunctionId string = functionCreation.properties.outputs.functionId
