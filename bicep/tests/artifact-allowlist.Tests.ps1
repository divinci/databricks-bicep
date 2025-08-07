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

Describe "Databricks Artifact Allowlist Bicep Module Tests" {
    Context "Positive Path Tests" {
        It "Should create an artifact allowlist with Maven artifacts" {
            $templateFile = "$PSScriptRoot/../modules/artifact-allowlist.bicep"
            $parameters = @{
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                ArtifactMatchers = @(
                    @{
                        artifact_type = "MAVEN"
                        match_type = "PREFIX_MATCH"
                        artifact = "org.apache.spark"
                    },
                    @{
                        artifact_type = "MAVEN"
                        match_type = "EXACT_MATCH"
                        artifact = "com.databricks:spark-xml_2.12:0.15.0"
                    }
                )
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.ArtifactMatchers.Value | Should -Not -BeNullOrEmpty
            $deployment.Outputs.CreatedBy.Value | Should -BeGreaterThan 0
            $deployment.Outputs.CreatedAt.Value | Should -BeGreaterThan 0
            
            $script:CreatedAllowlist = $true
        }
        
        It "Should create an artifact allowlist with PyPI packages" {
            $templateFile = "$PSScriptRoot/../modules/artifact-allowlist.bicep"
            $parameters = @{
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                ArtifactMatchers = @(
                    @{
                        artifact_type = "PYPI"
                        match_type = "PREFIX_MATCH"
                        artifact = "pandas"
                    },
                    @{
                        artifact_type = "PYPI"
                        match_type = "EXACT_MATCH"
                        artifact = "numpy==1.21.0"
                    }
                )
                CreatedBy = 12345
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.CreatedBy.Value | Should -Be 12345
            
            $script:CreatedPyPiAllowlist = $true
        }
    }
    
    Context "Negative Path Tests" {
        It "Should fail with empty artifact matchers" {
            $templateFile = "$PSScriptRoot/../modules/artifact-allowlist.bicep"
            $parameters = @{
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                ArtifactMatchers = @()
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
        # Note: Artifact allowlists are typically workspace-wide settings
        # Cleanup may not be necessary or possible depending on API design
        if ($script:CreatedAllowlist -or $script:CreatedPyPiAllowlist) {
            Write-Host "Artifact allowlist cleanup may require manual intervention"
            Write-Host "Consider resetting allowlist to default state if needed"
        }
    }
}
