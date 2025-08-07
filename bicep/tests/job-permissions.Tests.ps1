BeforeAll {
    Import-Module Pester -Force
    
    $script:TestResourceGroup = "rg-bicep-databricks-test"
    $script:TestLocation = "East US"
    $script:TestWorkspaceUrl = $env:DATABRICKS_WORKSPACE_URL
    $script:TestToken = $env:DATABRICKS_TOKEN
    
    if (-not $script:TestWorkspaceUrl -or -not $script:TestToken) {
        throw "Required environment variables DATABRICKS_WORKSPACE_URL and DATABRICKS_TOKEN must be set"
    }
    
    # Create a test job first
    $script:TestJobId = ""
}

Describe "Databricks Job Permissions Bicep Module Tests" {
    BeforeAll {
        # Create a test job for permissions testing
        Write-Host "Creating test job for permissions tests"
        $jobConfig = @{
            name = "test-permissions-job-$(Get-Random)"
            tasks = @(
                @{
                    task_key = "test_task"
                    notebook_task = @{
                        notebook_path = "/Shared/test-notebook"
                    }
                    new_cluster = @{
                        spark_version = "13.3.x-scala2.12"
                        node_type_id = "i3.xlarge"
                        num_workers = 1
                    }
                }
            )
        } | ConvertTo-Json -Depth 10
        
        try {
            $secureToken = ConvertTo-SecureString $script:TestToken -AsPlainText -Force
            $createResponse = & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                -Method "POST" `
                -UrlPath "/api/2.1/jobs/create" `
                -Body $jobConfig `
                -DatabricksToken $secureToken `
                -WorkspaceUrl $script:TestWorkspaceUrl
            
            $jobResult = $createResponse | ConvertFrom-Json
            $script:TestJobId = $jobResult.job_id
            Write-Host "Created test job with ID: $($script:TestJobId)"
        }
        catch {
            Write-Warning "Failed to create test job: $($_.Exception.Message)"
        }
    }
    
    Context "Positive Path Tests" {
        It "Should set job permissions with CAN_VIEW access" {
            if (-not $script:TestJobId) {
                Set-ItResult -Skipped -Because "Test job creation failed"
                return
            }
            
            $templateFile = "$PSScriptRoot/../modules/job-permissions.bicep"
            $parameters = @{
                JobId = $script:TestJobId
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                AccessControlList = @(
                    @{
                        user_name = "test-viewer@example.com"
                        permission_level = "CAN_VIEW"
                    }
                )
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.ObjectId.Value | Should -Be $script:TestJobId
            $deployment.Outputs.ObjectType.Value | Should -Be "job"
            $deployment.Outputs.AccessControlList.Value | Should -Not -BeNullOrEmpty
            $deployment.Outputs.AccessControlList.Value | Should -Match "CAN_VIEW"
        }
        
        It "Should set job permissions with CAN_MANAGE_RUN access" {
            if (-not $script:TestJobId) {
                Set-ItResult -Skipped -Because "Test job creation failed"
                return
            }
            
            $templateFile = "$PSScriptRoot/../modules/job-permissions.bicep"
            $parameters = @{
                JobId = $script:TestJobId
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                AccessControlList = @(
                    @{
                        user_name = "test-operator@example.com"
                        permission_level = "CAN_MANAGE_RUN"
                    },
                    @{
                        group_name = "job-viewers"
                        permission_level = "CAN_VIEW"
                    }
                )
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.AccessControlList.Value | Should -Match "CAN_MANAGE_RUN"
            $deployment.Outputs.AccessControlList.Value | Should -Match "job-viewers"
        }
        
        It "Should set job permissions with IS_OWNER access" {
            if (-not $script:TestJobId) {
                Set-ItResult -Skipped -Because "Test job creation failed"
                return
            }
            
            $templateFile = "$PSScriptRoot/../modules/job-permissions.bicep"
            $parameters = @{
                JobId = $script:TestJobId
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                AccessControlList = @(
                    @{
                        user_name = "test-owner@example.com"
                        permission_level = "IS_OWNER"
                    }
                )
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.AccessControlList.Value | Should -Match "IS_OWNER"
        }
    }
    
    Context "Negative Path Tests" {
        It "Should fail with empty job ID" {
            $templateFile = "$PSScriptRoot/../modules/job-permissions.bicep"
            $parameters = @{
                JobId = ""
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                AccessControlList = @(
                    @{
                        user_name = "test-user@example.com"
                        permission_level = "CAN_VIEW"
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
            $templateFile = "$PSScriptRoot/../modules/job-permissions.bicep"
            $parameters = @{
                JobId = $script:TestJobId
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
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
        # Cleanup test job
        if ($script:TestJobId) {
            Write-Host "Cleaning up test job: $($script:TestJobId)"
            try {
                $secureToken = ConvertTo-SecureString $script:TestToken -AsPlainText -Force
                & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                    -Method "POST" `
                    -UrlPath "/api/2.1/jobs/delete" `
                    -Body (@{ job_id = $script:TestJobId } | ConvertTo-Json) `
                    -DatabricksToken $secureToken `
                    -WorkspaceUrl $script:TestWorkspaceUrl
            }
            catch {
                Write-Warning "Failed to cleanup test job: $($_.Exception.Message)"
            }
        }
    }
}
