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

Describe "Databricks Spark Version Bicep Module Tests" {
    Context "Positive Path Tests" {
        It "Should get Spark version information for 13.3.x-scala2.12" {
            $templateFile = "$PSScriptRoot/../modules/spark-version.bicep"
            $parameters = @{
                SparkVersionKey = "13.3.x-scala2.12"
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                IncludeBeta = $false
                IncludeMl = $true
                IncludeGenomics = $false
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.SparkVersionKey.Value | Should -Be "13.3.x-scala2.12"
            $deployment.Outputs.SparkVersionName.Value | Should -Not -BeNullOrEmpty
            $deployment.Outputs.IsBeta.Value | Should -BeOfType [bool]
            $deployment.Outputs.IsMl.Value | Should -BeOfType [bool]
            $deployment.Outputs.IsGenomics.Value | Should -BeOfType [bool]
            $deployment.Outputs.IsLts.Value | Should -BeOfType [bool]
        }
        
        It "Should get Spark version information including beta versions" {
            $templateFile = "$PSScriptRoot/../modules/spark-version.bicep"
            $parameters = @{
                SparkVersionKey = "13.3.x-scala2.12"
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                IncludeBeta = $true
                IncludeMl = $true
                IncludeGenomics = $true
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.SparkVersionKey.Value | Should -Be "13.3.x-scala2.12"
        }
        
        It "Should get Spark version information for LTS version" {
            $templateFile = "$PSScriptRoot/../modules/spark-version.bicep"
            $parameters = @{
                SparkVersionKey = "12.2.x-scala2.12"
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                IncludeBeta = $false
                IncludeMl = $true
                IncludeGenomics = $false
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.SparkVersionKey.Value | Should -Be "12.2.x-scala2.12"
        }
    }
    
    Context "Negative Path Tests" {
        It "Should fail with empty Spark version key" {
            $templateFile = "$PSScriptRoot/../modules/spark-version.bicep"
            $parameters = @{
                SparkVersionKey = ""
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                IncludeBeta = $false
                IncludeMl = $true
                IncludeGenomics = $false
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
        
        It "Should fail with invalid Spark version key" {
            $templateFile = "$PSScriptRoot/../modules/spark-version.bicep"
            $parameters = @{
                SparkVersionKey = "invalid.spark.version"
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                IncludeBeta = $false
                IncludeMl = $true
                IncludeGenomics = $false
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
