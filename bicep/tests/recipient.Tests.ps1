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

Describe "Databricks Recipient Bicep Module Tests" {
    Context "Positive Path Tests" {
        It "Should create a basic Delta Sharing recipient" {
            $templateFile = "$PSScriptRoot/../modules/recipient.bicep"
            $parameters = @{
                RecipientName = "test_recipient_$(Get-Random)"
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                Comment = "Test Delta Sharing recipient created by Bicep module"
                AuthenticationType = "TOKEN"
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.RecipientName.Value | Should -Be $parameters.RecipientName
            $deployment.Outputs.Comment.Value | Should -Be $parameters.Comment
            $deployment.Outputs.AuthenticationType.Value | Should -Be "TOKEN"
            $deployment.Outputs.CreatedAt.Value | Should -BeGreaterThan 0
            $deployment.Outputs.UpdatedAt.Value | Should -BeGreaterThan 0
            
            $script:CreatedRecipientName = $deployment.Outputs.RecipientName.Value
        }
        
        It "Should create a recipient with sharing identifier" {
            $templateFile = "$PSScriptRoot/../modules/recipient.bicep"
            $parameters = @{
                RecipientName = "test_sharing_recipient_$(Get-Random)"
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                Comment = "Recipient with sharing identifier"
                SharingIdentifier = "sharing-$(Get-Random)"
                AuthenticationType = "DATABRICKS"
                DataRecipientGlobalMetastoreId = "metastore-$(Get-Random)"
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.SharingIdentifier.Value | Should -Be $parameters.SharingIdentifier
            $deployment.Outputs.AuthenticationType.Value | Should -Be "DATABRICKS"
            
            $script:CreatedSharingRecipientName = $deployment.Outputs.RecipientName.Value
        }
    }
    
    Context "Negative Path Tests" {
        It "Should fail with empty recipient name" {
            $templateFile = "$PSScriptRoot/../modules/recipient.bicep"
            $parameters = @{
                RecipientName = ""
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
    if ($script:CreatedRecipientName) {
        Write-Host "Cleaning up Delta Sharing recipient: $($script:CreatedRecipientName)"
        try {
            $secureToken = ConvertTo-SecureString $script:TestToken -AsPlainText -Force
            & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                -Method "DELETE" `
                -UrlPath "/api/2.1/unity-catalog/recipients/$($script:CreatedRecipientName)" `
                -DatabricksToken $secureToken `
                -WorkspaceUrl $script:TestWorkspaceUrl
        }
        catch {
            Write-Warning "Failed to cleanup Delta Sharing recipient $($script:CreatedRecipientName): $($_.Exception.Message)"
        }
    }
    
    if ($script:CreatedSharingRecipientName) {
        Write-Host "Cleaning up sharing Delta Sharing recipient: $($script:CreatedSharingRecipientName)"
        try {
            $secureToken = ConvertTo-SecureString $script:TestToken -AsPlainText -Force
            & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                -Method "DELETE" `
                -UrlPath "/api/2.1/unity-catalog/recipients/$($script:CreatedSharingRecipientName)" `
                -DatabricksToken $secureToken `
                -WorkspaceUrl $script:TestWorkspaceUrl
        }
        catch {
            Write-Warning "Failed to cleanup sharing Delta Sharing recipient $($script:CreatedSharingRecipientName): $($_.Exception.Message)"
        }
    }
}
