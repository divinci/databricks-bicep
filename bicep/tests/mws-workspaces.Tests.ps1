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

Describe "Databricks MWS Workspaces Bicep Module Tests" {
    Context "Positive Path Tests" {
        It "Should create a basic MWS workspace" {
            $templateFile = "$PSScriptRoot/../modules/mws-workspaces.bicep"
            $parameters = @{
                WorkspaceName = "test-workspace-$(Get-Random)"
                AccountId = $script:TestAccountId
                AccountToken = $script:TestAccountToken
                AwsRegion = "us-east-1"
                CredentialsId = "test-credentials-id"
                StorageConfigurationId = "test-storage-config-id"
                PricingTier = "PREMIUM"
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.WorkspaceId.Value | Should -BeGreaterThan 0
            $deployment.Outputs.WorkspaceName.Value | Should -Be $parameters.WorkspaceName
            $deployment.Outputs.WorkspaceUrl.Value | Should -Not -BeNullOrEmpty
            $deployment.Outputs.AwsRegion.Value | Should -Be "us-east-1"
            $deployment.Outputs.PricingTier.Value | Should -Be "PREMIUM"
            $deployment.Outputs.CreationTime.Value | Should -BeGreaterThan 0
            
            $script:CreatedWorkspaceId = $deployment.Outputs.WorkspaceId.Value
        }
        
        It "Should create a workspace with custom network configuration" {
            $templateFile = "$PSScriptRoot/../modules/mws-workspaces.bicep"
            $parameters = @{
                WorkspaceName = "test-network-workspace-$(Get-Random)"
                AccountId = $script:TestAccountId
                AccountToken = $script:TestAccountToken
                AwsRegion = "us-west-2"
                CredentialsId = "test-credentials-id"
                StorageConfigurationId = "test-storage-config-id"
                NetworkId = "test-network-id"
                IsNoPublicIpEnabled = $true
                CustomTags = @{
                    "environment" = "test"
                    "team" = "platform"
                }
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.AwsRegion.Value | Should -Be "us-west-2"
            
            $script:CreatedNetworkWorkspaceId = $deployment.Outputs.WorkspaceId.Value
        }
    }
    
    Context "Negative Path Tests" {
        It "Should fail with empty workspace name" {
            $templateFile = "$PSScriptRoot/../modules/mws-workspaces.bicep"
            $parameters = @{
                WorkspaceName = ""
                AccountId = $script:TestAccountId
                AccountToken = $script:TestAccountToken
                AwsRegion = "us-east-1"
                CredentialsId = "test-credentials-id"
                StorageConfigurationId = "test-storage-config-id"
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
    if ($script:CreatedWorkspaceId) {
        Write-Host "Cleaning up MWS workspace: $($script:CreatedWorkspaceId)"
        try {
            $secureToken = ConvertTo-SecureString $script:TestAccountToken -AsPlainText -Force
            & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                -Method "DELETE" `
                -UrlPath "/api/2.0/accounts/$($script:TestAccountId)/workspaces/$($script:CreatedWorkspaceId)" `
                -DatabricksToken $secureToken `
                -WorkspaceUrl "https://accounts.cloud.databricks.com"
        }
        catch {
            Write-Warning "Failed to cleanup MWS workspace $($script:CreatedWorkspaceId): $($_.Exception.Message)"
        }
    }
    
    if ($script:CreatedNetworkWorkspaceId) {
        Write-Host "Cleaning up network MWS workspace: $($script:CreatedNetworkWorkspaceId)"
        try {
            $secureToken = ConvertTo-SecureString $script:TestAccountToken -AsPlainText -Force
            & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                -Method "DELETE" `
                -UrlPath "/api/2.0/accounts/$($script:TestAccountId)/workspaces/$($script:CreatedNetworkWorkspaceId)" `
                -DatabricksToken $secureToken `
                -WorkspaceUrl "https://accounts.cloud.databricks.com"
        }
        catch {
            Write-Warning "Failed to cleanup network MWS workspace $($script:CreatedNetworkWorkspaceId): $($_.Exception.Message)"
        }
    }
}
