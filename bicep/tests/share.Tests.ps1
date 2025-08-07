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

Describe "Databricks Share Bicep Module Tests" {
    Context "Positive Path Tests" {
        It "Should create a basic Delta Sharing share" {
            $templateFile = "$PSScriptRoot/../modules/share.bicep"
            $parameters = @{
                ShareName = "test_share_$(Get-Random)"
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                Comment = "Test Delta Sharing share created by Bicep module"
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.ShareName.Value | Should -Be $parameters.ShareName
            $deployment.Outputs.ShareId.Value | Should -Not -BeNullOrEmpty
            $deployment.Outputs.Comment.Value | Should -Be $parameters.Comment
            $deployment.Outputs.CreatedAt.Value | Should -BeGreaterThan 0
            $deployment.Outputs.UpdatedAt.Value | Should -BeGreaterThan 0
            
            $script:CreatedShareName = $deployment.Outputs.ShareName.Value
        }
        
        It "Should create a share with storage configuration" {
            $templateFile = "$PSScriptRoot/../modules/share.bicep"
            $parameters = @{
                ShareName = "test_storage_share_$(Get-Random)"
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                Comment = "Share with storage configuration"
                StorageRoot = "s3://test-share-bucket-$(Get-Random)/share/"
                StorageLocation = "s3://test-share-bucket-$(Get-Random)/location/"
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.StorageRoot.Value | Should -Be $parameters.StorageRoot
            $deployment.Outputs.StorageLocation.Value | Should -Be $parameters.StorageLocation
            
            $script:CreatedStorageShareName = $deployment.Outputs.ShareName.Value
        }
    }
    
    Context "Negative Path Tests" {
        It "Should fail with empty share name" {
            $templateFile = "$PSScriptRoot/../modules/share.bicep"
            $parameters = @{
                ShareName = ""
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
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
    if ($script:CreatedShareName) {
        Write-Host "Cleaning up Delta Sharing share: $($script:CreatedShareName)"
        try {
            $secureToken = ConvertTo-SecureString $script:TestToken -AsPlainText -Force
            & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                -Method "DELETE" `
                -UrlPath "/api/2.1/unity-catalog/shares/$($script:CreatedShareName)" `
                -DatabricksToken $secureToken `
                -WorkspaceUrl $script:TestWorkspaceUrl
        }
        catch {
            Write-Warning "Failed to cleanup Delta Sharing share $($script:CreatedShareName): $($_.Exception.Message)"
        }
    }
    
    if ($script:CreatedStorageShareName) {
        Write-Host "Cleaning up storage Delta Sharing share: $($script:CreatedStorageShareName)"
        try {
            $secureToken = ConvertTo-SecureString $script:TestToken -AsPlainText -Force
            & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                -Method "DELETE" `
                -UrlPath "/api/2.1/unity-catalog/shares/$($script:CreatedStorageShareName)" `
                -DatabricksToken $secureToken `
                -WorkspaceUrl $script:TestWorkspaceUrl
        }
        catch {
            Write-Warning "Failed to cleanup storage Delta Sharing share $($script:CreatedStorageShareName): $($_.Exception.Message)"
        }
    }
}
