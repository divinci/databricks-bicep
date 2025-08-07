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

Describe "Databricks Storage Credential Bicep Module Tests" {
    Context "Positive Path Tests" {
        It "Should create a basic AWS IAM role storage credential" {
            $templateFile = "$PSScriptRoot/../modules/storage-credential.bicep"
            $parameters = @{
                CredentialName = "test-aws-credential-$(Get-Random)"
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                Comment = "Test AWS storage credential created by Bicep module"
                AwsIamRole = @{
                    role_arn = "arn:aws:iam::123456789012:role/test-databricks-role"
                }
                SkipValidation = $true
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.CredentialName.Value | Should -Be $parameters.CredentialName
            $deployment.Outputs.CredentialId.Value | Should -Not -BeNullOrEmpty
            $deployment.Outputs.Comment.Value | Should -Be $parameters.Comment
            $deployment.Outputs.ReadOnly.Value | Should -Be $false
            $deployment.Outputs.CreatedAt.Value | Should -BeGreaterThan 0
            
            $script:CreatedAwsCredentialName = $deployment.Outputs.CredentialName.Value
        }
        
        It "Should create an Azure service principal storage credential" {
            $templateFile = "$PSScriptRoot/../modules/storage-credential.bicep"
            $parameters = @{
                CredentialName = "test-azure-credential-$(Get-Random)"
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                Comment = "Test Azure storage credential"
                AzureServicePrincipal = @{
                    directory_id = "12345678-1234-1234-1234-123456789012"
                    application_id = "87654321-4321-4321-4321-210987654321"
                    client_secret = "test-client-secret"
                }
                ReadOnly = $true
                SkipValidation = $true
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.ReadOnly.Value | Should -Be $true
            
            $script:CreatedAzureCredentialName = $deployment.Outputs.CredentialName.Value
        }
    }
    
    Context "Negative Path Tests" {
        It "Should fail with empty credential name" {
            $templateFile = "$PSScriptRoot/../modules/storage-credential.bicep"
            $parameters = @{
                CredentialName = ""
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                AwsIamRole = @{
                    role_arn = "arn:aws:iam::123456789012:role/test-role"
                }
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
    if ($script:CreatedAwsCredentialName) {
        Write-Host "Cleaning up AWS storage credential: $($script:CreatedAwsCredentialName)"
        try {
            $secureToken = ConvertTo-SecureString $script:TestToken -AsPlainText -Force
            & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                -Method "DELETE" `
                -UrlPath "/api/2.1/unity-catalog/storage-credentials/$($script:CreatedAwsCredentialName)" `
                -DatabricksToken $secureToken `
                -WorkspaceUrl $script:TestWorkspaceUrl
        }
        catch {
            Write-Warning "Failed to cleanup AWS storage credential $($script:CreatedAwsCredentialName): $($_.Exception.Message)"
        }
    }
    
    if ($script:CreatedAzureCredentialName) {
        Write-Host "Cleaning up Azure storage credential: $($script:CreatedAzureCredentialName)"
        try {
            $secureToken = ConvertTo-SecureString $script:TestToken -AsPlainText -Force
            & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                -Method "DELETE" `
                -UrlPath "/api/2.1/unity-catalog/storage-credentials/$($script:CreatedAzureCredentialName)" `
                -DatabricksToken $secureToken `
                -WorkspaceUrl $script:TestWorkspaceUrl
        }
        catch {
            Write-Warning "Failed to cleanup Azure storage credential $($script:CreatedAzureCredentialName): $($_.Exception.Message)"
        }
    }
}
