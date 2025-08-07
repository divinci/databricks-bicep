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

Describe "Databricks Cluster Policy Bicep Module Tests" {
    Context "Positive Path Tests" {
        It "Should create a basic cluster policy" {
            $templateFile = "$PSScriptRoot/../modules/cluster-policy.bicep"
            $policyDefinition = @{
                "spark_version" = @{
                    "type" = "fixed"
                    "value" = "13.3.x-scala2.12"
                }
                "node_type_id" = @{
                    "type" = "allowlist"
                    "values" = @("i3.xlarge", "i3.2xlarge")
                }
                "num_workers" = @{
                    "type" = "range"
                    "min" = 1
                    "max" = 10
                }
            } | ConvertTo-Json -Depth 10
            
            $parameters = @{
                PolicyName = "test-cluster-policy-$(Get-Random)"
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                Definition = $policyDefinition
                Description = "Test cluster policy created by Bicep module"
                MaxClustersPerUser = 5
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.PolicyId.Value | Should -Not -BeNullOrEmpty
            $deployment.Outputs.PolicyName.Value | Should -Be $parameters.PolicyName
            $deployment.Outputs.Description.Value | Should -Be $parameters.Description
            $deployment.Outputs.MaxClustersPerUser.Value | Should -Be 5
            $deployment.Outputs.CreatedAtTimestamp.Value | Should -BeGreaterThan 0
            $deployment.Outputs.CreatorUserName.Value | Should -Not -BeNullOrEmpty
            
            $script:CreatedPolicyId = $deployment.Outputs.PolicyId.Value
        }
        
        It "Should create a cluster policy with libraries" {
            $templateFile = "$PSScriptRoot/../modules/cluster-policy.bicep"
            $policyDefinition = @{
                "spark_version" = @{
                    "type" = "fixed"
                    "value" = "13.3.x-scala2.12"
                }
            } | ConvertTo-Json -Depth 10
            
            $parameters = @{
                PolicyName = "test-library-policy-$(Get-Random)"
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                Definition = $policyDefinition
                Description = "Policy with libraries"
                Libraries = @(
                    @{
                        pypi = @{
                            package = "pandas==1.5.0"
                        }
                    },
                    @{
                        maven = @{
                            coordinates = "org.apache.spark:spark-sql_2.12:3.4.0"
                        }
                    }
                )
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.Description.Value | Should -Be "Policy with libraries"
            
            $script:CreatedLibraryPolicyId = $deployment.Outputs.PolicyId.Value
        }
    }
    
    Context "Negative Path Tests" {
        It "Should fail with empty policy name" {
            $templateFile = "$PSScriptRoot/../modules/cluster-policy.bicep"
            $parameters = @{
                PolicyName = ""
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                Definition = "{}"
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
        
        It "Should fail with empty definition" {
            $templateFile = "$PSScriptRoot/../modules/cluster-policy.bicep"
            $parameters = @{
                PolicyName = "test-invalid-policy"
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                Definition = ""
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

AfterAll {
    if ($script:CreatedPolicyId) {
        Write-Host "Cleaning up cluster policy: $($script:CreatedPolicyId)"
        try {
            $secureToken = ConvertTo-SecureString $script:TestToken -AsPlainText -Force
            & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                -Method "POST" `
                -UrlPath "/api/2.0/policies/clusters/delete" `
                -Body (@{ policy_id = $script:CreatedPolicyId } | ConvertTo-Json) `
                -DatabricksToken $secureToken `
                -WorkspaceUrl $script:TestWorkspaceUrl
        }
        catch {
            Write-Warning "Failed to cleanup cluster policy $($script:CreatedPolicyId): $($_.Exception.Message)"
        }
    }
    
    if ($script:CreatedLibraryPolicyId) {
        Write-Host "Cleaning up library cluster policy: $($script:CreatedLibraryPolicyId)"
        try {
            $secureToken = ConvertTo-SecureString $script:TestToken -AsPlainText -Force
            & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                -Method "POST" `
                -UrlPath "/api/2.0/policies/clusters/delete" `
                -Body (@{ policy_id = $script:CreatedLibraryPolicyId } | ConvertTo-Json) `
                -DatabricksToken $secureToken `
                -WorkspaceUrl $script:TestWorkspaceUrl
        }
        catch {
            Write-Warning "Failed to cleanup library cluster policy $($script:CreatedLibraryPolicyId): $($_.Exception.Message)"
        }
    }
}
