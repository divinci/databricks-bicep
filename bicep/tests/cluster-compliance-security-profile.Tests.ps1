BeforeAll {
    Import-Module Pester -Force
    
    $script:TestResourceGroup = "rg-bicep-databricks-test"
    $script:TestLocation = "East US"
    $script:TestWorkspaceUrl = $env:DATABRICKS_WORKSPACE_URL
    $script:TestToken = $env:DATABRICKS_TOKEN
    
    if (-not $script:TestWorkspaceUrl -or -not $script:TestToken) {
        throw "Required environment variables DATABRICKS_WORKSPACE_URL and DATABRICKS_TOKEN must be set"
    }
    
    # Create a test cluster first
    $script:TestClusterId = ""
}

Describe "Databricks Cluster Compliance Security Profile Bicep Module Tests" {
    BeforeAll {
        # Create a test cluster for compliance security profile
        Write-Host "Creating test cluster for compliance security profile tests"
        $clusterConfig = @{
            cluster_name = "test-compliance-cluster-$(Get-Random)"
            spark_version = "13.3.x-scala2.12"
            node_type_id = "i3.xlarge"
            num_workers = 1
            autotermination_minutes = 30
        } | ConvertTo-Json -Depth 10
        
        try {
            $secureToken = ConvertTo-SecureString $script:TestToken -AsPlainText -Force
            $createResponse = & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                -Method "POST" `
                -UrlPath "/api/2.0/clusters/create" `
                -Body $clusterConfig `
                -DatabricksToken $secureToken `
                -WorkspaceUrl $script:TestWorkspaceUrl
            
            $clusterResult = $createResponse | ConvertFrom-Json
            $script:TestClusterId = $clusterResult.cluster_id
            Write-Host "Created test cluster with ID: $($script:TestClusterId)"
        }
        catch {
            Write-Warning "Failed to create test cluster: $($_.Exception.Message)"
        }
    }
    
    Context "Positive Path Tests" {
        It "Should enable cluster compliance security profile" {
            if (-not $script:TestClusterId) {
                Set-ItResult -Skipped -Because "Test cluster creation failed"
                return
            }
            
            $templateFile = "$PSScriptRoot/../modules/cluster-compliance-security-profile.bicep"
            $parameters = @{
                ClusterId = $script:TestClusterId
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                IsEnabled = $true
                ComplianceStandards = @("SOC2", "HIPAA")
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.ClusterId.Value | Should -Be $script:TestClusterId
            $deployment.Outputs.IsEnabled.Value | Should -Be $true
            $deployment.Outputs.ComplianceStandards.Value | Should -Not -BeNullOrEmpty
        }
        
        It "Should disable cluster compliance security profile" {
            if (-not $script:TestClusterId) {
                Set-ItResult -Skipped -Because "Test cluster creation failed"
                return
            }
            
            $templateFile = "$PSScriptRoot/../modules/cluster-compliance-security-profile.bicep"
            $parameters = @{
                ClusterId = $script:TestClusterId
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                IsEnabled = $false
                ComplianceStandards = @()
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.IsEnabled.Value | Should -Be $false
        }
    }
    
    Context "Negative Path Tests" {
        It "Should fail with empty cluster ID" {
            $templateFile = "$PSScriptRoot/../modules/cluster-compliance-security-profile.bicep"
            $parameters = @{
                ClusterId = ""
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                IsEnabled = $true
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
        # Cleanup test cluster
        if ($script:TestClusterId) {
            Write-Host "Cleaning up test cluster: $($script:TestClusterId)"
            try {
                $secureToken = ConvertTo-SecureString $script:TestToken -AsPlainText -Force
                & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                    -Method "POST" `
                    -UrlPath "/api/2.0/clusters/permanent-delete" `
                    -Body (@{ cluster_id = $script:TestClusterId } | ConvertTo-Json) `
                    -DatabricksToken $secureToken `
                    -WorkspaceUrl $script:TestWorkspaceUrl
            }
            catch {
                Write-Warning "Failed to cleanup test cluster: $($_.Exception.Message)"
            }
        }
    }
}
