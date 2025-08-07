BeforeAll {
    Import-Module Pester -Force
    
    $script:TestResourceGroup = "rg-bicep-databricks-test"
    $script:TestLocation = "East US"
    $script:TestWorkspaceUrl = $env:DATABRICKS_WORKSPACE_URL
    $script:TestToken = $env:DATABRICKS_TOKEN
    
    if (-not $script:TestWorkspaceUrl -or -not $script:TestToken) {
        throw "Required environment variables DATABRICKS_WORKSPACE_URL and DATABRICKS_TOKEN must be set"
    }
}

Describe "Databricks System Schema Bicep Module Tests" {
    Context "Positive Path Tests" {
        It "Should enable system schema for access" {
            $templateFile = "$PSScriptRoot/../modules/system-schema.bicep"
            $parameters = @{
                SchemaName = "access"
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                State = "ENABLE"
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.SchemaName.Value | Should -Be "access"
            $deployment.Outputs.State.Value | Should -Be "ENABLE"
            $deployment.Outputs.MetastoreId.Value | Should -Not -BeNullOrEmpty
            
            $script:EnabledSchemaName = $deployment.Outputs.SchemaName.Value
        }
        
        It "Should enable system schema for billing" {
            $templateFile = "$PSScriptRoot/../modules/system-schema.bicep"
            $parameters = @{
                SchemaName = "billing"
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                State = "ENABLE"
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.SchemaName.Value | Should -Be "billing"
            
            $script:EnabledBillingSchemaName = $deployment.Outputs.SchemaName.Value
        }
        
        It "Should disable system schema" {
            $templateFile = "$PSScriptRoot/../modules/system-schema.bicep"
            $parameters = @{
                SchemaName = "access"
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                State = "DISABLE"
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.State.Value | Should -Be "DISABLE"
        }
    }
    
    Context "Negative Path Tests" {
        It "Should fail with empty schema name" {
            $templateFile = "$PSScriptRoot/../modules/system-schema.bicep"
            $parameters = @{
                SchemaName = ""
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                State = "ENABLE"
            }
            
            { 
                New-AzResourceGroupDeployment `
                    -ResourceGroupName $script:TestResourceGroup `
                    -TemplateFile $templateFile `
                    -TemplateParameterObject $parameters `
                    -Mode Incremental `
                    -ErrorAction Stop
            } | Should -Throw
        }
        
        It "Should fail with invalid state" {
            $templateFile = "$PSScriptRoot/../modules/system-schema.bicep"
            $parameters = @{
                SchemaName = "access"
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                State = "INVALID"
            }
            
            { 
                New-AzResourceGroupDeployment `
                    -ResourceGroupName $script:TestResourceGroup `
                    -TemplateFile $templateFile `
                    -TemplateParameterObject $parameters `
                    -Mode Incremental `
                    -ErrorAction Stop
            } | Should -Throw
        }
    }
    
    AfterAll {
        # Note: System schemas are typically managed at the metastore level
        # and don't require explicit cleanup in tests
    }
}
