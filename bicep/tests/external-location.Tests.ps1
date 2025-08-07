BeforeAll {
    Import-Module Pester -Force
    
    $script:TestResourceGroup = "rg-bicep-databricks-test"
    $script:TestLocation = "East US"
    $script:TestWorkspaceUrl = $env:DATABRICKS_WORKSPACE_URL
    $script:TestToken = $env:DATABRICKS_TOKEN
    
    if (-not $script:TestWorkspaceUrl -or -not $script:TestToken) {
        throw "Required environment variables DATABRICKS_WORKSPACE_URL and DATABRICKS_TOKEN must be set"
    }
    
    # Create a test storage credential first
    $script:TestCredentialName = "test-external-location-credential-$(Get-Random)"
}

Describe "Databricks External Location Bicep Module Tests" {
    BeforeAll {
        # Create a test storage credential first
        Write-Host "Creating test storage credential: $($script:TestCredentialName)"
        $credentialConfig = @{
            name = $script:TestCredentialName
            comment = "Test credential for external location tests"
            skip_validation = $true
            aws_iam_role = @{
                role_arn = "arn:aws:iam::123456789012:role/test-role"
            }
        } | ConvertTo-Json -Depth 10
        
        try {
            $secureToken = ConvertTo-SecureString $script:TestToken -AsPlainText -Force
            $createResponse = & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                -Method "POST" `
                -UrlPath "/api/2.1/unity-catalog/storage-credentials" `
                -Body $credentialConfig `
                -DatabricksToken $secureToken `
                -WorkspaceUrl $script:TestWorkspaceUrl
            Write-Host "Created test storage credential successfully"
        }
        catch {
            Write-Warning "Failed to create test storage credential: $($_.Exception.Message)"
        }
    }
    
    Context "Positive Path Tests" {
        It "Should create a basic external location" {
            $templateFile = "$PSScriptRoot/../modules/external-location.bicep"
            $parameters = @{
                LocationName = "test-external-location-$(Get-Random)"
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                Url = "s3://test-bucket-$(Get-Random)/path/"
                CredentialName = $script:TestCredentialName
                Comment = "Test external location created by Bicep module"
                SkipValidation = $true
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.LocationName.Value | Should -Be $parameters.LocationName
            $deployment.Outputs.Url.Value | Should -Be $parameters.Url
            $deployment.Outputs.CredentialName.Value | Should -Be $script:TestCredentialName
            $deployment.Outputs.Comment.Value | Should -Be $parameters.Comment
            $deployment.Outputs.ReadOnly.Value | Should -Be $false
            $deployment.Outputs.CreatedAt.Value | Should -BeGreaterThan 0
            
            $script:CreatedLocationName = $deployment.Outputs.LocationName.Value
        }
        
        It "Should create a read-only external location" {
            $templateFile = "$PSScriptRoot/../modules/external-location.bicep"
            $parameters = @{
                LocationName = "test-readonly-location-$(Get-Random)"
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                Url = "s3://test-readonly-bucket-$(Get-Random)/path/"
                CredentialName = $script:TestCredentialName
                Comment = "Read-only test external location"
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
            
            $script:CreatedReadOnlyLocationName = $deployment.Outputs.LocationName.Value
        }
    }
    
    Context "Negative Path Tests" {
        It "Should fail with empty location name" {
            $templateFile = "$PSScriptRoot/../modules/external-location.bicep"
            $parameters = @{
                LocationName = ""
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                Url = "s3://test-bucket/path/"
                CredentialName = $script:TestCredentialName
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
        
        It "Should fail with non-existent credential" {
            $templateFile = "$PSScriptRoot/../modules/external-location.bicep"
            $parameters = @{
                LocationName = "test-invalid-location"
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                Url = "s3://test-bucket/path/"
                CredentialName = "non-existent-credential"
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
        # Cleanup external locations
        if ($script:CreatedLocationName) {
            Write-Host "Cleaning up external location: $($script:CreatedLocationName)"
            try {
                $secureToken = ConvertTo-SecureString $script:TestToken -AsPlainText -Force
                & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                    -Method "DELETE" `
                    -UrlPath "/api/2.1/unity-catalog/external-locations/$($script:CreatedLocationName)" `
                    -DatabricksToken $secureToken `
                    -WorkspaceUrl $script:TestWorkspaceUrl
            }
            catch {
                Write-Warning "Failed to cleanup external location $($script:CreatedLocationName): $($_.Exception.Message)"
            }
        }
        
        if ($script:CreatedReadOnlyLocationName) {
            Write-Host "Cleaning up read-only external location: $($script:CreatedReadOnlyLocationName)"
            try {
                $secureToken = ConvertTo-SecureString $script:TestToken -AsPlainText -Force
                & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                    -Method "DELETE" `
                    -UrlPath "/api/2.1/unity-catalog/external-locations/$($script:CreatedReadOnlyLocationName)" `
                    -DatabricksToken $secureToken `
                    -WorkspaceUrl $script:TestWorkspaceUrl
            }
            catch {
                Write-Warning "Failed to cleanup read-only external location $($script:CreatedReadOnlyLocationName): $($_.Exception.Message)"
            }
        }
        
        # Cleanup test storage credential
        if ($script:TestCredentialName) {
            Write-Host "Cleaning up test storage credential: $($script:TestCredentialName)"
            try {
                $secureToken = ConvertTo-SecureString $script:TestToken -AsPlainText -Force
                & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                    -Method "DELETE" `
                    -UrlPath "/api/2.1/unity-catalog/storage-credentials/$($script:TestCredentialName)" `
                    -DatabricksToken $secureToken `
                    -WorkspaceUrl $script:TestWorkspaceUrl
            }
            catch {
                Write-Warning "Failed to cleanup test storage credential $($script:TestCredentialName): $($_.Exception.Message)"
            }
        }
    }
}
