BeforeAll {
    Import-Module Pester -Force
    
    $script:TestResourceGroup = "rg-bicep-databricks-test"
    $script:TestLocation = "East US"
    $script:TestWorkspaceUrl = $env:DATABRICKS_WORKSPACE_URL
    $script:TestToken = $env:DATABRICKS_TOKEN
    
    if (-not $script:TestWorkspaceUrl -or -not $script:TestToken) {
        throw "Required environment variables DATABRICKS_WORKSPACE_URL and DATABRICKS_TOKEN must be set"
    }
    
    # Create test notebook first
    $script:TestNotebookPath = "/Shared/test-permissions-notebook-$(Get-Random)"
    $script:TestNotebookId = ""
}

Describe "Databricks Workspace Object Permissions Bicep Module Tests" {
    BeforeAll {
        # Create a test notebook for permissions testing
        Write-Host "Creating test notebook for permissions tests: $($script:TestNotebookPath)"
        $notebookContent = @"
# Databricks notebook source
print("Test notebook for permissions")
"@
        $encodedContent = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($notebookContent))
        
        $notebookConfig = @{
            path = $script:TestNotebookPath
            content = $encodedContent
            language = "PYTHON"
            format = "SOURCE"
            overwrite = $true
        } | ConvertTo-Json -Depth 10
        
        try {
            $secureToken = ConvertTo-SecureString $script:TestToken -AsPlainText -Force
            $createResponse = & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                -Method "POST" `
                -UrlPath "/api/2.0/workspace/import" `
                -Body $notebookConfig `
                -DatabricksToken $secureToken `
                -WorkspaceUrl $script:TestWorkspaceUrl
            
            # Get notebook details to get object ID
            $notebookDetailsResponse = & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                -Method "GET" `
                -UrlPath "/api/2.0/workspace/get-status?path=$([System.Web.HttpUtility]::UrlEncode($script:TestNotebookPath))" `
                -DatabricksToken $secureToken `
                -WorkspaceUrl $script:TestWorkspaceUrl
            
            $notebookDetails = $notebookDetailsResponse | ConvertFrom-Json
            $script:TestNotebookId = $notebookDetails.object_id
            Write-Host "Created test notebook with ID: $($script:TestNotebookId)"
        }
        catch {
            Write-Warning "Failed to create test notebook: $($_.Exception.Message)"
        }
    }
    
    Context "Positive Path Tests" {
        It "Should set notebook permissions with CAN_READ access" {
            if (-not $script:TestNotebookId) {
                Set-ItResult -Skipped -Because "Test notebook creation failed"
                return
            }
            
            $templateFile = "$PSScriptRoot/../modules/workspace-object-permissions.bicep"
            $parameters = @{
                ObjectId = $script:TestNotebookId
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                ObjectType = "notebook"
                AccessControlList = @(
                    @{
                        user_name = "test-user@example.com"
                        permission_level = "CAN_READ"
                    }
                )
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.ObjectId.Value | Should -Be $script:TestNotebookId
            $deployment.Outputs.ObjectType.Value | Should -Be "notebook"
            $deployment.Outputs.AccessControlList.Value | Should -Not -BeNullOrEmpty
            $deployment.Outputs.AccessControlList.Value | Should -Match "CAN_READ"
        }
        
        It "Should set notebook permissions with CAN_EDIT access" {
            if (-not $script:TestNotebookId) {
                Set-ItResult -Skipped -Because "Test notebook creation failed"
                return
            }
            
            $templateFile = "$PSScriptRoot/../modules/workspace-object-permissions.bicep"
            $parameters = @{
                ObjectId = $script:TestNotebookId
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                ObjectType = "notebook"
                AccessControlList = @(
                    @{
                        user_name = "test-editor@example.com"
                        permission_level = "CAN_EDIT"
                    },
                    @{
                        group_name = "test-group"
                        permission_level = "CAN_READ"
                    }
                )
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.AccessControlList.Value | Should -Match "CAN_EDIT"
            $deployment.Outputs.AccessControlList.Value | Should -Match "test-group"
        }
        
        It "Should set notebook permissions with CAN_MANAGE access" {
            if (-not $script:TestNotebookId) {
                Set-ItResult -Skipped -Because "Test notebook creation failed"
                return
            }
            
            $templateFile = "$PSScriptRoot/../modules/workspace-object-permissions.bicep"
            $parameters = @{
                ObjectId = $script:TestNotebookId
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                ObjectType = "notebook"
                AccessControlList = @(
                    @{
                        user_name = "test-admin@example.com"
                        permission_level = "CAN_MANAGE"
                    }
                )
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.AccessControlList.Value | Should -Match "CAN_MANAGE"
        }
    }
    
    Context "Negative Path Tests" {
        It "Should fail with empty object ID" {
            $templateFile = "$PSScriptRoot/../modules/workspace-object-permissions.bicep"
            $parameters = @{
                ObjectId = ""
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                ObjectType = "notebook"
                AccessControlList = @(
                    @{
                        user_name = "test-user@example.com"
                        permission_level = "CAN_READ"
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
        
        It "Should fail with invalid object type" {
            $templateFile = "$PSScriptRoot/../modules/workspace-object-permissions.bicep"
            $parameters = @{
                ObjectId = $script:TestNotebookId
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                ObjectType = "invalid_type"
                AccessControlList = @(
                    @{
                        user_name = "test-user@example.com"
                        permission_level = "CAN_READ"
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
        
        It "Should fail with empty access control list" {
            $templateFile = "$PSScriptRoot/../modules/workspace-object-permissions.bicep"
            $parameters = @{
                ObjectId = $script:TestNotebookId
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                ObjectType = "notebook"
                AccessControlList = @()
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
        # Cleanup test notebook
        if ($script:TestNotebookPath) {
            Write-Host "Cleaning up test notebook: $($script:TestNotebookPath)"
            try {
                $secureToken = ConvertTo-SecureString $script:TestToken -AsPlainText -Force
                & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                    -Method "POST" `
                    -UrlPath "/api/2.0/workspace/delete" `
                    -Body (@{ path = $script:TestNotebookPath; recursive = $false } | ConvertTo-Json) `
                    -DatabricksToken $secureToken `
                    -WorkspaceUrl $script:TestWorkspaceUrl
            }
            catch {
                Write-Warning "Failed to cleanup test notebook: $($_.Exception.Message)"
            }
        }
    }
}
