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

Describe "Databricks Metastore Bicep Module Tests" {
    Context "Positive Path Tests" {
        It "Should create a basic Unity Catalog metastore" {
            $templateFile = "$PSScriptRoot/../modules/metastore.bicep"
            $parameters = @{
                MetastoreName = "test-metastore-$(Get-Random)"
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                StorageRoot = "s3://test-metastore-bucket-$(Get-Random)/metastore/"
                Region = "us-east-1"
                DeltaSharingScope = "INTERNAL"
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.MetastoreName.Value | Should -Be $parameters.MetastoreName
            $deployment.Outputs.MetastoreId.Value | Should -Not -BeNullOrEmpty
            $deployment.Outputs.StorageRoot.Value | Should -Be $parameters.StorageRoot
            $deployment.Outputs.Region.Value | Should -Be "us-east-1"
            $deployment.Outputs.DeltaSharingScope.Value | Should -Be "INTERNAL"
            $deployment.Outputs.CreatedAt.Value | Should -BeGreaterThan 0
            
            $script:CreatedMetastoreId = $deployment.Outputs.MetastoreId.Value
        }
        
        It "Should create a metastore with delta sharing configuration" {
            $templateFile = "$PSScriptRoot/../modules/metastore.bicep"
            $parameters = @{
                MetastoreName = "test-sharing-metastore-$(Get-Random)"
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                StorageRoot = "s3://test-sharing-metastore-bucket-$(Get-Random)/metastore/"
                Region = "us-west-2"
                DeltaSharingScope = "INTERNAL_AND_EXTERNAL"
                DeltaSharingRecipientTokenLifetimeInSeconds = 86400
                DeltaSharingOrganizationName = "test-org"
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.DeltaSharingScope.Value | Should -Be "INTERNAL_AND_EXTERNAL"
            $deployment.Outputs.DeltaSharingOrganizationName.Value | Should -Be "test-org"
            
            $script:CreatedSharingMetastoreId = $deployment.Outputs.MetastoreId.Value
        }
    }
    
    Context "Negative Path Tests" {
        It "Should fail with empty metastore name" {
            $templateFile = "$PSScriptRoot/../modules/metastore.bicep"
            $parameters = @{
                MetastoreName = ""
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                StorageRoot = "s3://test-bucket/metastore/"
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
        
        It "Should fail with empty storage root" {
            $templateFile = "$PSScriptRoot/../modules/metastore.bicep"
            $parameters = @{
                MetastoreName = "test-invalid-metastore"
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                StorageRoot = ""
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
    if ($script:CreatedMetastoreId) {
        Write-Host "Cleaning up metastore: $($script:CreatedMetastoreId)"
        try {
            $secureToken = ConvertTo-SecureString $script:TestToken -AsPlainText -Force
            & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                -Method "DELETE" `
                -UrlPath "/api/2.1/unity-catalog/metastores/$($script:CreatedMetastoreId)" `
                -DatabricksToken $secureToken `
                -WorkspaceUrl $script:TestWorkspaceUrl
        }
        catch {
            Write-Warning "Failed to cleanup metastore $($script:CreatedMetastoreId): $($_.Exception.Message)"
        }
    }
    
    if ($script:CreatedSharingMetastoreId) {
        Write-Host "Cleaning up sharing metastore: $($script:CreatedSharingMetastoreId)"
        try {
            $secureToken = ConvertTo-SecureString $script:TestToken -AsPlainText -Force
            & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                -Method "DELETE" `
                -UrlPath "/api/2.1/unity-catalog/metastores/$($script:CreatedSharingMetastoreId)" `
                -DatabricksToken $secureToken `
                -WorkspaceUrl $script:TestWorkspaceUrl
        }
        catch {
            Write-Warning "Failed to cleanup sharing metastore $($script:CreatedSharingMetastoreId): $($_.Exception.Message)"
        }
    }
}
