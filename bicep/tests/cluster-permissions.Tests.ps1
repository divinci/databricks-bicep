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

Describe "Databricks Cluster Permissions Bicep Module Tests" {
    BeforeAll {
        # Create a test cluster for permissions testing
        Write-Host "Creating test cluster for permissions tests"
        $clusterConfig = @{
            cluster_name = "test-permissions-cluster-$(Get-Random)"
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
        It "Should set cluster permissions with CAN_ATTACH_TO access" {
            if (-not $script:TestClusterId) {
                Set-ItResult -Skipped -Because "Test cluster creation failed"
                return
            }
            
            $templateFile = "$PSScriptRoot/../modules/cluster-permissions.bicep"
            $parameters = @{
                ClusterId = $script:TestClusterId
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                AccessControlList = @(
                    @{
                        user_name = "test-user@example.com"
                        permission_level = "CAN_ATTACH_TO"
                    }
                )
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.ObjectId.Value | Should -Be $script:TestClusterId
            $deployment.Outputs.ObjectType.Value | Should -Be "cluster"
            $deployment.Outputs.AccessControlList.Value | Should -Not -BeNullOrEmpty
            $deployment.Outputs.AccessControlList.Value | Should -Match "CAN_ATTACH_TO"
        }
        
        It "Should set cluster permissions with CAN_RESTART access" {
            if (-not $script:TestClusterId) {
                Set-ItResult -Skipped -Because "Test cluster creation failed"
                return
            }
            
            $templateFile = "$PSScriptRoot/../modules/cluster-permissions.bicep"
            $parameters = @{
                ClusterId = $script:TestClusterId
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                AccessControlList = @(
                    @{
                        user_name = "test-operator@example.com"
                        permission_level = "CAN_RESTART"
                    },
                    @{
                        group_name = "cluster-users"
                        permission_level = "CAN_ATTACH_TO"
                    }
                )
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.AccessControlList.Value | Should -Match "CAN_RESTART"
            $deployment.Outputs.AccessControlList.Value | Should -Match "cluster-users"
        }
        
        It "Should set cluster permissions with CAN_MANAGE access" {
            if (-not $script:TestClusterId) {
                Set-ItResult -Skipped -Because "Test cluster creation failed"
                return
            }
            
            $templateFile = "$PSScriptRoot/../modules/cluster-permissions.bicep"
            $parameters = @{
                ClusterId = $script:TestClusterId
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                AccessControlList = @(
                    @{
                        user_name = "test-admin@example.com"
                        permission_level = "CAN_MANAGE"
                    }
                )
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.AccessControlList.Value | Should -Match "CAN_MANAGE"
        }
    }
    
    Context "Negative Path Tests" {
        It "Should fail with empty cluster ID" {
            $templateFile = "$PSScriptRoot/../modules/cluster-permissions.bicep"
            $parameters = @{
                ClusterId = ""
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                AccessControlList = @(
                    @{
                        user_name = "test-user@example.com"
                        permission_level = "CAN_ATTACH_TO"
                    }
                )
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
        
        It "Should fail with empty access control list" {
            $templateFile = "$PSScriptRoot/../modules/cluster-permissions.bicep"
            $parameters = @{
                ClusterId = $script:TestClusterId
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                AccessControlList = @()
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
