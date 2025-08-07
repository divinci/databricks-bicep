BeforeAll {
    Import-Module Pester -Force
    
    $script:TestResourceGroup = "rg-bicep-databricks-test"
    $script:TestLocation = "East US"
    $script:TestWorkspaceUrl = $env:DATABRICKS_WORKSPACE_URL
    $script:TestToken = $env:DATABRICKS_TOKEN
    
    if (-not $script:TestWorkspaceUrl -or -not $script:TestToken) {
        throw "Required environment variables DATABRICKS_WORKSPACE_URL and DATABRICKS_TOKEN must be set"
    }
    
    # Create a test cluster for permissions testing
    $script:TestClusterId = $null
}

Describe "Databricks Permissions Bicep Module Tests" {
    BeforeAll {
        # Create a test cluster first
        Write-Host "Creating test cluster for permissions testing..."
        $clusterConfig = @{
            cluster_name = "test-permissions-cluster-$(Get-Random)"
            spark_version = "13.3.x-scala2.12"
            node_type_id = "Standard_DS3_v2"
            num_workers = 1
            auto_termination_minutes = 30
        } | ConvertTo-Json -Depth 10
        
        try {
            $secureToken = ConvertTo-SecureString $script:TestToken -AsPlainText -Force
            $createResponse = & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                -Method "POST" `
                -UrlPath "/api/2.1/clusters/create" `
                -Body $clusterConfig `
                -DatabricksToken $secureToken `
                -WorkspaceUrl $script:TestWorkspaceUrl
            
            $cluster = $createResponse | ConvertFrom-Json
            $script:TestClusterId = $cluster.cluster_id
            Write-Host "Created test cluster: $($script:TestClusterId)"
        }
        catch {
            Write-Warning "Failed to create test cluster: $($_.Exception.Message)"
        }
    }
    
    Context "Positive Path Tests" {
        It "Should set cluster permissions" -Skip:($null -eq $script:TestClusterId) {
            $templateFile = "$PSScriptRoot/../modules/permissions.bicep"
            $parameters = @{
                ObjectId = $script:TestClusterId
                ObjectType = "cluster"
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                AccessControlList = @(
                    @{
                        group_name = "users"
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
        }
    }
    
    Context "Negative Path Tests" {
        It "Should fail with invalid object ID" {
            $templateFile = "$PSScriptRoot/../modules/permissions.bicep"
            $parameters = @{
                ObjectId = "invalid-object-id"
                ObjectType = "cluster"
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                AccessControlList = @(
                    @{
                        group_name = "users"
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
    }
    
    AfterAll {
        # Cleanup test cluster
        if ($script:TestClusterId) {
            Write-Host "Cleaning up test cluster: $($script:TestClusterId)"
            try {
                $secureToken = ConvertTo-SecureString $script:TestToken -AsPlainText -Force
                & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                    -Method "POST" `
                    -UrlPath "/api/2.1/clusters/permanent-delete" `
                    -Body "{`"cluster_id`": `"$($script:TestClusterId)`"}" `
                    -DatabricksToken $secureToken `
                    -WorkspaceUrl $script:TestWorkspaceUrl
            }
            catch {
                Write-Warning "Failed to cleanup test cluster $($script:TestClusterId): $($_.Exception.Message)"
            }
        }
    }
}
