param(
    
    [Parameter(Mandatory = $false)]
    [string]$sa_password,

    [Parameter(Mandatory = $false)]
    [string]$ACCEPT_EULA,

    [Parameter(Mandatory = $false)]
    [string]$attach_dbs,
    
    [Parameter(Mandatory = $true)]
    [string]$pbirs_user,

    [Parameter(Mandatory = $true)]
    [string]$pbirs_password
    
)

    
.\sqlstart -sa_password $sa_password -ACCEPT_EULA $ACCEPT_EULA -attach_dbs \"$attach_dbs\" -Verbose


Write-Verbose "PBIRS Config"
.\configurePBIRS -Verbose

# ── Migrate PBIRS catalog from Windows auth to Custom auth ────────────────────
# After InitializeReportServer, the catalog contains Windows principals
# (BUILTIN\Administrators, \Everyone).  When PBIRS runs with our custom auth
# extension those principals trigger Windows AuthZ API calls that fail in a
# container (no domain), causing NullReferenceException in UpdateSecurityPolicies.
# Fix: replace all Windows-auth users with a single custom-auth admin user that
# matches the runtime cookie credential ($pbirs_user).
if ($pbirs_user -ne "_") {
    Write-Verbose "Migrating PBIRS catalog principals to custom auth for user: $pbirs_user"

    $migrateSql = @"
IF EXISTS (SELECT 1 FROM Users WHERE AuthType = 1)
BEGIN
    -- Ensure the custom-auth admin user row exists
    IF NOT EXISTS (SELECT 1 FROM Users WHERE UserName = N'$pbirs_user' AND AuthType = 2)
    BEGIN
        DECLARE @newID uniqueidentifier = NEWID()
        INSERT INTO Users (UserID, Sid, UserType, UserName, AuthType)
        VALUES (@newID, NULL, 1, N'$pbirs_user', 2)
    END

    DECLARE @adminID  uniqueidentifier
    SELECT  @adminID  = UserID FROM Users WHERE UserName = N'$pbirs_user' AND AuthType = 2

    DECLARE @cmRoleID uniqueidentifier
    SELECT  @cmRoleID = RoleID FROM Roles WHERE RoleName = 'Content Manager'
    DECLARE @saRoleID uniqueidentifier
    SELECT  @saRoleID = RoleID FROM Roles WHERE RoleName = 'System Administrator'

    -- Root-folder item policy (PolicyFlag = 0): grant Content Manager
    DECLARE @rootPolicyID uniqueidentifier
    SELECT TOP 1 @rootPolicyID = PolicyID FROM Policies WHERE PolicyFlag = 0

    IF @rootPolicyID IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM PolicyUserRole
        WHERE PolicyID = @rootPolicyID AND UserID = @adminID AND RoleID = @cmRoleID)
    BEGIN
        INSERT INTO PolicyUserRole (ID, PolicyID, UserID, RoleID)
        VALUES (NEWID(), @rootPolicyID, @adminID, @cmRoleID)
    END

    -- System policy (PolicyFlag = 1): grant System Administrator
    DECLARE @sysPolicyID uniqueidentifier
    SELECT TOP 1 @sysPolicyID = PolicyID FROM Policies WHERE PolicyFlag = 1

    IF @sysPolicyID IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM PolicyUserRole
        WHERE PolicyID = @sysPolicyID AND UserID = @adminID AND RoleID = @saRoleID)
    BEGIN
        INSERT INTO PolicyUserRole (ID, PolicyID, UserID, RoleID)
        VALUES (NEWID(), @sysPolicyID, @adminID, @saRoleID)
    END

    -- Remove role assignments for original Windows principals
    DELETE FROM PolicyUserRole
    WHERE UserID IN (SELECT UserID FROM Users WHERE AuthType = 1)

    -- Convert Windows users to custom auth (keep rows for FK constraints from Catalog)
    UPDATE Users SET AuthType = 2 WHERE AuthType = 1
END
"@

    try {
        Import-Module -name 'C:\Program Files (x86)\Microsoft SQL Server\150\Tools\PowerShell\Modules\sqlps' -ErrorAction SilentlyContinue
        Invoke-Sqlcmd -ServerInstance '(local)' -Database 'ReportServer' -Query $migrateSql
        Write-Verbose "Catalog migration complete."
    } catch {
        Write-Warning "Catalog migration failed (non-fatal): $_"
    }
}

.\newadmin -username $pbirs_user -password $pbirs_password -Verbose

$lastCheck = (Get-Date).AddSeconds(-2) 
while ($true) { 
    Get-EventLog -LogName Application -Source "MSSQL*" -After $lastCheck | Select-Object TimeGenerated, EntryType, Message	 
   
    $lastCheck = Get-Date
    Start-Sleep -Seconds 2 
}
