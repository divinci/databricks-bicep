BeforeAll {
    Import-Module Pester -Force
    
    $script:TestResourceGroup = "rg-bicep-databricks-test"
    $script:TestLocation = "East US"
    $script:TestAccountId = $env:DATABRICKS_ACCOUNT_ID
    $script:TestAccountToken = $env:DATABRICKS_ACCOUNT_TOKEN
    
    if (-not $script:TestAccountId -or -not $script:TestAccountToken) {
        throw "Required environment variables DATABRICKS_ACCOUNT_ID and DATABRICKS_ACCOUNT_TOKEN must be set"
    }
}

Describe "Databricks MWS Storage Configurations Bicep Module Tests" {
    Context "Positive Path Tests" {
        It "Should create basic MWS storage configuration" {
            $templateFile = "$PSScriptRoot/../modules/mws-storage-configurations.bicep"
            $parameters = @{
                StorageConfigurationName = "test-storage-config-$(Get-Random)"
                AccountId = $script:TestAccountId
                AccountToken = $script:TestAccountToken
                BucketName = "test-databricks-bucket-$(Get-Random)"
                BucketRegion = "us-east-1"
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.StorageConfigurationId.Value | Should -Not -BeNullOrEmpty
            $deployment.Outputs.StorageConfigurationName.Value | Should -Be $parameters.StorageConfigurationName
            $deployment.Outputs.BucketName.Value | Should -Be $parameters.BucketName
            $deployment.Outputs.BucketRegion.Value | Should -Be "us-east-1"
            $deployment.Outputs.CreationTime.Value | Should -BeGreaterThan 0
            
            $script:CreatedStorageConfigurationId = $deployment.Outputs.StorageConfigurationId.Value
        }
        
        It "Should create MWS storage configuration without region" {
            $templateFile = "$PSScriptRoot/../modules/mws-storage-configurations.bicep"
            $parameters = @{
                StorageConfigurationName = "test-no-region-storage-$(Get-Random)"
                AccountId = $script:TestAccountId
                AccountToken = $script:TestAccountToken
                BucketName = "test-no-region-bucket-$(Get-Random)"
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.BucketName.Value | Should -Be $parameters.BucketName
            
            $script:CreatedNoRegionStorageConfigurationId = $deployment.Outputs.StorageConfigurationId.Value
        }
    }
    
    Context "Negative Path Tests" {
        It "Should fail with empty storage configuration name" {
            $templateFile = "$PSScriptRoot/../modules/mws-storage-configurations.bicep"
            $parameters = @{
                StorageConfigurationName = ""
                AccountId = $script:TestAccountId
                AccountToken = $script:TestAccountToken
                BucketName = "test-bucket"
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
        
        It "Should fail with empty bucket name" {
            $templateFile = "$PSScriptRoot/../modules/mws-storage-configurations.bicep"
            $parameters = @{
                StorageConfigurationName = "test-invalid-storage"
                AccountId = $script:TestAccountId
                AccountToken = $script:TestAccountToken
                BucketName = ""
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
    if ($script:CreatedStorageConfigurationId) {
        Write-Host "Cleaning up MWS storage configuration: $($script:CreatedStorageConfigurationId)"
        try {
            $secureToken = ConvertTo-SecureString $script:TestAccountToken -AsPlainText -Force
            & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                -Method "DELETE" `
                -UrlPath "/api/2.0/accounts/$($script:TestAccountId)/storage-configurations/$($script:CreatedStorageConfigurationId)" `
                -DatabricksToken $secureToken `
                -WorkspaceUrl "https://accounts.cloud.databricks.com"
        }
        catch {
            Write-Warning "Failed to cleanup MWS storage configuration $($script:CreatedStorageConfigurationId): $($_.Exception.Message)"
        }
    }
    
    if ($script:CreatedNoRegionStorageConfigurationId) {
        Write-Host "Cleaning up no-region MWS storage configuration: $($script:CreatedNoRegionStorageConfigurationId)"
        try {
            $secureToken = ConvertTo-SecureString $script:TestAccountToken -AsPlainText -Force
            & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                -Method "DELETE" `
                -UrlPath "/api/2.0/accounts/$($script:TestAccountId)/storage-configurations/$($script:CreatedNoRegionStorageConfigurationId)" `
                -DatabricksToken $secureToken `
                -WorkspaceUrl "https://accounts.cloud.databricks.com"
        }
        catch {
            Write-Warning "Failed to cleanup no-region MWS storage configuration $($script:CreatedNoRegionStorageConfigurationId): $($_.Exception.Message)"
        }
    }
}
