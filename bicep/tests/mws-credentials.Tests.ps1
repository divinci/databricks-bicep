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

Describe "Databricks MWS Credentials Bicep Module Tests" {
    Context "Positive Path Tests" {
        It "Should create basic MWS credentials" {
            $templateFile = "$PSScriptRoot/../modules/mws-credentials.bicep"
            $parameters = @{
                CredentialsName = "test-credentials-$(Get-Random)"
                AccountId = $script:TestAccountId
                AccountToken = $script:TestAccountToken
                RoleArn = "arn:aws:iam::123456789012:role/test-databricks-role"
                ExternalId = "external-$(Get-Random)"
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.CredentialsId.Value | Should -Not -BeNullOrEmpty
            $deployment.Outputs.CredentialsName.Value | Should -Be $parameters.CredentialsName
            $deployment.Outputs.RoleArn.Value | Should -Be $parameters.RoleArn
            $deployment.Outputs.ExternalId.Value | Should -Be $parameters.ExternalId
            $deployment.Outputs.CreationTime.Value | Should -BeGreaterThan 0
            
            $script:CreatedCredentialsId = $deployment.Outputs.CredentialsId.Value
        }
        
        It "Should create MWS credentials without external ID" {
            $templateFile = "$PSScriptRoot/../modules/mws-credentials.bicep"
            $parameters = @{
                CredentialsName = "test-simple-credentials-$(Get-Random)"
                AccountId = $script:TestAccountId
                AccountToken = $script:TestAccountToken
                RoleArn = "arn:aws:iam::123456789012:role/test-simple-role"
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.RoleArn.Value | Should -Be $parameters.RoleArn
            
            $script:CreatedSimpleCredentialsId = $deployment.Outputs.CredentialsId.Value
        }
    }
    
    Context "Negative Path Tests" {
        It "Should fail with empty credentials name" {
            $templateFile = "$PSScriptRoot/../modules/mws-credentials.bicep"
            $parameters = @{
                CredentialsName = ""
                AccountId = $script:TestAccountId
                AccountToken = $script:TestAccountToken
                RoleArn = "arn:aws:iam::123456789012:role/test-role"
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
        
        It "Should fail with invalid role ARN" {
            $templateFile = "$PSScriptRoot/../modules/mws-credentials.bicep"
            $parameters = @{
                CredentialsName = "test-invalid-credentials"
                AccountId = $script:TestAccountId
                AccountToken = $script:TestAccountToken
                RoleArn = "invalid-arn"
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
    if ($script:CreatedCredentialsId) {
        Write-Host "Cleaning up MWS credentials: $($script:CreatedCredentialsId)"
        try {
            $secureToken = ConvertTo-SecureString $script:TestAccountToken -AsPlainText -Force
            & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                -Method "DELETE" `
                -UrlPath "/api/2.0/accounts/$($script:TestAccountId)/credentials/$($script:CreatedCredentialsId)" `
                -DatabricksToken $secureToken `
                -WorkspaceUrl "https://accounts.cloud.databricks.com"
        }
        catch {
            Write-Warning "Failed to cleanup MWS credentials $($script:CreatedCredentialsId): $($_.Exception.Message)"
        }
    }
    
    if ($script:CreatedSimpleCredentialsId) {
        Write-Host "Cleaning up simple MWS credentials: $($script:CreatedSimpleCredentialsId)"
        try {
            $secureToken = ConvertTo-SecureString $script:TestAccountToken -AsPlainText -Force
            & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                -Method "DELETE" `
                -UrlPath "/api/2.0/accounts/$($script:TestAccountId)/credentials/$($script:CreatedSimpleCredentialsId)" `
                -DatabricksToken $secureToken `
                -WorkspaceUrl "https://accounts.cloud.databricks.com"
        }
        catch {
            Write-Warning "Failed to cleanup simple MWS credentials $($script:CreatedSimpleCredentialsId): $($_.Exception.Message)"
        }
    }
}
