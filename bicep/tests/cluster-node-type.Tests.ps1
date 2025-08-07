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

Describe "Databricks Cluster Node Type Bicep Module Tests" {
    Context "Positive Path Tests" {
        It "Should get node type information for i3.xlarge" {
            $templateFile = "$PSScriptRoot/../modules/cluster-node-type.bicep"
            $parameters = @{
                NodeTypeId = "i3.xlarge"
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                IncludeLocalDisk = $false
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.NodeTypeId.Value | Should -Be "i3.xlarge"
            $deployment.Outputs.MemoryMb.Value | Should -BeGreaterThan 0
            $deployment.Outputs.NumCores.Value | Should -BeGreaterThan 0
            $deployment.Outputs.Description.Value | Should -Not -BeNullOrEmpty
            $deployment.Outputs.InstanceTypeId.Value | Should -Not -BeNullOrEmpty
            $deployment.Outputs.IsIoOptimized.Value | Should -BeOfType [bool]
            $deployment.Outputs.NumGpus.Value | Should -BeGreaterOrEqual 0
            $deployment.Outputs.NodeInfo.Value | Should -Not -BeNullOrEmpty
        }
        
        It "Should get node type information with local disk details" {
            $templateFile = "$PSScriptRoot/../modules/cluster-node-type.bicep"
            $parameters = @{
                NodeTypeId = "i3.xlarge"
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                IncludeLocalDisk = $true
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.NodeTypeId.Value | Should -Be "i3.xlarge"
            $deployment.Outputs.LocalDisks.Value | Should -BeGreaterOrEqual 0
            $deployment.Outputs.LocalDiskSizeGb.Value | Should -BeGreaterOrEqual 0
        }
        
        It "Should get node type information for m5.large" {
            $templateFile = "$PSScriptRoot/../modules/cluster-node-type.bicep"
            $parameters = @{
                NodeTypeId = "m5.large"
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                IncludeLocalDisk = $false
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.NodeTypeId.Value | Should -Be "m5.large"
            $deployment.Outputs.NumCores.Value | Should -BeGreaterThan 0
        }
    }
    
    Context "Negative Path Tests" {
        It "Should fail with empty node type ID" {
            $templateFile = "$PSScriptRoot/../modules/cluster-node-type.bicep"
            $parameters = @{
                NodeTypeId = ""
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                IncludeLocalDisk = $false
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
        
        It "Should fail with invalid node type ID" {
            $templateFile = "$PSScriptRoot/../modules/cluster-node-type.bicep"
            $parameters = @{
                NodeTypeId = "invalid.node.type"
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                IncludeLocalDisk = $false
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
}
