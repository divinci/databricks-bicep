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

Describe "Databricks Mount Bicep Module Tests" {
    Context "Positive Path Tests" {
        It "Should create a basic mount point" -Skip {
            # Skip this test as it requires actual storage account setup
            # This is a placeholder for when proper test storage is configured
            
            $templateFile = "$PSScriptRoot/../modules/mount.bicep"
            $parameters = @{
                MountName = "test-mount-$(Get-Random)"
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                Source = "abfss://test@teststorage.dfs.core.windows.net/"
                ExtraConfigs = @{
                    "fs.azure.account.auth.type.teststorage.dfs.core.windows.net" = "OAuth"
                    "fs.azure.account.oauth.provider.type.teststorage.dfs.core.windows.net" = "org.apache.hadoop.fs.azurebfs.oauth2.ClientCredsTokenProvider"
                    "fs.azure.account.oauth2.client.id.teststorage.dfs.core.windows.net" = "test-client-id"
                    "fs.azure.account.oauth2.client.secret.teststorage.dfs.core.windows.net" = "test-client-secret"
                    "fs.azure.account.oauth2.client.endpoint.teststorage.dfs.core.windows.net" = "https://login.microsoftonline.com/test-tenant-id/oauth2/token"
                }
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.MountName.Value | Should -Be $parameters.MountName
            $deployment.Outputs.MountPath.Value | Should -Be "/mnt/$($parameters.MountName)"
            
            $script:CreatedMountName = $deployment.Outputs.MountName.Value
        }
    }
    
    Context "Negative Path Tests" {
        It "Should fail with empty mount name" {
            $templateFile = "$PSScriptRoot/../modules/mount.bicep"
            $parameters = @{
                MountName = ""
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                Source = "abfss://test@teststorage.dfs.core.windows.net/"
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
        
        It "Should fail with invalid source URI" {
            $templateFile = "$PSScriptRoot/../modules/mount.bicep"
            $parameters = @{
                MountName = "test-invalid-mount"
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                Source = "invalid-source-uri"
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
    if ($script:CreatedMountName) {
        Write-Host "Cleaning up mount: $($script:CreatedMountName)"
        try {
            $secureToken = ConvertTo-SecureString $script:TestToken -AsPlainText -Force
            $unmountBody = @{
                mount_name = $script:CreatedMountName
            } | ConvertTo-Json
            
            & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                -Method "POST" `
                -UrlPath "/api/2.0/dbfs/unmount" `
                -Body $unmountBody `
                -DatabricksToken $secureToken `
                -WorkspaceUrl $script:TestWorkspaceUrl
        }
        catch {
            Write-Warning "Failed to cleanup mount $($script:CreatedMountName): $($_.Exception.Message)"
        }
    }
}
