<#
.SYNOPSIS
    Installs the PowerBI.CustomAuth cookie-based authentication extension into
    Power BI Report Server (PBIRS).

.DESCRIPTION
    1. Copies PowerBI.CustomAuth.dll to ReportServer\bin, Portal, and PowerBI dirs.
    2. Patches rsreportserver.config:
       - Registers Security (authorization) and Authentication extensions as "Forms"
       - Sets AuthenticationTypes to <Custom/>
       - Adds <EnableAuthPersistence>true</EnableAuthPersistence>
       - Adds <MachineKey> for cross-process FormsAuth cookie validation
       - Adds PassThroughCookies for both loggedInUser and sqlAuthCookie
    3. Patches rssrvpolicy.config to grant FullTrust to the extension assembly.
    4. Patches web.config:
       - mode="Forms" with <forms> element (loginUrl, name, timeout, path)
       - identity impersonate="false"
       - <authorization><deny users="?" /></authorization>
       - <machineKey> matching the one in rsreportserver.config
    5. Patches Portal WebHost.exe.config with the same machineKey.
    6. Creates logon.aspx (translates loggedInUser cookie → FormsAuth ticket).
#>

$ErrorActionPreference = 'Stop'

# ── Paths ──────────────────────────────────────────────────────────────────────
$pbirs   = "C:\Program Files\Microsoft Power BI Report Server\PBIRS\ReportServer"
$bin     = Join-Path $pbirs "bin"
$portal  = "C:\Program Files\Microsoft Power BI Report Server\PBIRS\Portal"
$powerbi = "C:\Program Files\Microsoft Power BI Report Server\PBIRS\PowerBI"
$dll     = "C:\CustomAuthExtension\bin\Release\net472\PowerBI.CustomAuth.dll"

# Static MachineKey for dev/eval (all three config files must share the same key).
$validationKey = "E5EC42B8B9B7608B290342C07AEE2B44ED8C0E0850BAFC5B4D3AE12FD69DE438D56B8EA50B6641F4311CDEF39B4160E2F3E10857F813A0B3C085B66E0233F45A"
$decryptionKey = "F0D6B285C88D1D2B9B8A0C34E5F6718A42D3E0B9C8A7F6E5D4C3B2A190807060"

# ── 1. Copy DLL to all required directories ───────────────────────────────────
Write-Host "[CustomAuth] Copying DLL..."
Copy-Item -Path $dll -Destination (Join-Path $bin "PowerBI.CustomAuth.dll") -Force
foreach ($dir in @($portal, $powerbi)) {
    if (Test-Path $dir) {
        Copy-Item -Path $dll -Destination (Join-Path $dir "PowerBI.CustomAuth.dll") -Force
    }
}
Write-Host "[CustomAuth] DLL copied to ReportServer, Portal, PowerBI."

# ── 2. Patch rsreportserver.config ─────────────────────────────────────────────
$rsConfig = Join-Path $pbirs "rsreportserver.config"
Write-Host "[CustomAuth] Patching $rsConfig"

[xml]$xml = Get-Content -Raw $rsConfig

# 2a. Extensions: Security (Authorization)
if (-not $xml.Configuration.Extensions) {
    $ext = $xml.CreateElement("Extensions")
    $xml.Configuration.AppendChild($ext) | Out-Null
}
$extNode = $xml.Configuration.Extensions

$oldSec = $extNode.SelectSingleNode("Security")
if ($oldSec) { $extNode.RemoveChild($oldSec) | Out-Null }
$secNode = $xml.CreateElement("Security")
$secExt  = $xml.CreateElement("Extension")
$secExt.SetAttribute("Name", "Forms")
$secExt.SetAttribute("Type", "PowerBI.CustomAuth.CookieAuthorizationExtension, PowerBI.CustomAuth")
$secNode.AppendChild($secExt) | Out-Null
$extNode.AppendChild($secNode) | Out-Null

# 2b. Extensions: Authentication
$oldAuth = $extNode.SelectSingleNode("Authentication")
if ($oldAuth) { $extNode.RemoveChild($oldAuth) | Out-Null }
$authNode = $xml.CreateElement("Authentication")
$authExt  = $xml.CreateElement("Extension")
$authExt.SetAttribute("Name", "Forms")
$authExt.SetAttribute("Type", "PowerBI.CustomAuth.CookieAuthExtension, PowerBI.CustomAuth")
$authNode.AppendChild($authExt) | Out-Null
$extNode.AppendChild($authNode) | Out-Null

# 2c. AuthenticationTypes → <Custom/>
$authSection = $xml.Configuration.Authentication
if (-not $authSection) {
    $authSection = $xml.CreateElement("Authentication")
    $xml.Configuration.AppendChild($authSection) | Out-Null
}
$authTypes = $authSection.SelectSingleNode("AuthenticationTypes")
if ($authTypes) { $authTypes.RemoveAll() } else {
    $authTypes = $xml.CreateElement("AuthenticationTypes")
    $authSection.AppendChild($authTypes) | Out-Null
}
$customNode = $xml.CreateElement("Custom")
$authTypes.AppendChild($customNode) | Out-Null

# 2d. EnableAuthPersistence
$eap = $authSection.SelectSingleNode("EnableAuthPersistence")
if (-not $eap) {
    $eap = $xml.CreateElement("EnableAuthPersistence")
    $authSection.AppendChild($eap) | Out-Null
}
$eap.InnerText = "true"

# 2e. MachineKey (under <Configuration>)
$mk = $xml.Configuration.SelectSingleNode("MachineKey")
if (-not $mk) {
    $mk = $xml.CreateElement("MachineKey")
    $xml.Configuration.AppendChild($mk) | Out-Null
}
$mk.SetAttribute("ValidationKey", $validationKey)
$mk.SetAttribute("DecryptionKey", $decryptionKey)
$mk.SetAttribute("Validation", "AES")
$mk.SetAttribute("Decryption", "AES")

# 2f. UI / PassThroughCookies (both loggedInUser AND sqlAuthCookie)
$uiNode = $xml.Configuration.SelectSingleNode("UI")
if (-not $uiNode) {
    $uiNode = $xml.CreateElement("UI")
    $xml.Configuration.AppendChild($uiNode) | Out-Null
}
$custAuth = $uiNode.SelectSingleNode("CustomAuthenticationUI")
if (-not $custAuth) {
    $custAuth = $xml.CreateElement("CustomAuthenticationUI")
    $uiNode.AppendChild($custAuth) | Out-Null
}
$ptCookies = $custAuth.SelectSingleNode("PassThroughCookies")
if (-not $ptCookies) {
    $ptCookies = $xml.CreateElement("PassThroughCookies")
    $custAuth.AppendChild($ptCookies) | Out-Null
}
foreach ($cookieName in @("sqlAuthCookie", "loggedInUser")) {
    $existing = $ptCookies.SelectSingleNode("PassThroughCookie[text()='$cookieName']")
    if (-not $existing) {
        $ptc = $xml.CreateElement("PassThroughCookie")
        $ptc.InnerText = $cookieName
        $ptCookies.AppendChild($ptc) | Out-Null
    }
}

$xml.Save($rsConfig)
Write-Host "[CustomAuth] rsreportserver.config updated."

# ── 3. Patch rssrvpolicy.config ────────────────────────────────────────────────
$policyConfig = Join-Path $pbirs "rssrvpolicy.config"
Write-Host "[CustomAuth] Patching $policyConfig"

[xml]$pol = Get-Content -Raw $policyConfig

# Find the MyComputer zone FirstMatchCodeGroup (where FullTrust entries live).
# This is the inner FirstMatchCodeGroup with Zone=MyComputer, not the root one.
$myComputerGroup = $pol.SelectSingleNode(
    "//CodeGroup[@class='FirstMatchCodeGroup']/CodeGroup[@class='FirstMatchCodeGroup']")
if (-not $myComputerGroup) {
    # Fallback: root FirstMatchCodeGroup
    $myComputerGroup = $pol.SelectSingleNode("//CodeGroup[@class='FirstMatchCodeGroup']")
}

if ($myComputerGroup) {
    # Remove any existing entry (may be in wrong location from prior runs)
    $existing = $pol.SelectNodes("//CodeGroup[@Name='PowerBI_CustomAuth']")
    foreach ($e in $existing) { $e.ParentNode.RemoveChild($e) | Out-Null }

    $cg = $pol.CreateElement("CodeGroup")
    $cg.SetAttribute("class",             "UnionCodeGroup")
    $cg.SetAttribute("version",           "1")
    $cg.SetAttribute("PermissionSetName", "FullTrust")
    $cg.SetAttribute("Name",              "PowerBI_CustomAuth")
    $cg.SetAttribute("Description",       "FullTrust for PowerBI Cookie Auth Extension")

    $mc = $pol.CreateElement("IMembershipCondition")
    $mc.SetAttribute("class",   "UrlMembershipCondition")
    $mc.SetAttribute("version", "1")
    $mc.SetAttribute("Url",     (Join-Path $bin "PowerBI.CustomAuth.dll"))
    $cg.AppendChild($mc) | Out-Null
    $myComputerGroup.AppendChild($cg) | Out-Null
    $pol.Save($policyConfig)
    Write-Host "[CustomAuth] rssrvpolicy.config updated."
} else {
    Write-Warning "[CustomAuth] Could not locate CodeGroup node in rssrvpolicy.config."
}

# ── 4. Patch ReportServer web.config ──────────────────────────────────────────
$webConfig = Join-Path $pbirs "web.config"
Write-Host "[CustomAuth] Patching $webConfig"
[xml]$webXml = Get-Content -Raw $webConfig

$sysWeb = $webXml.configuration.'system.web'

# 4a. authentication mode="Forms" + <forms> child
$authEl = $sysWeb.authentication
if ($authEl) {
    $authEl.SetAttribute("mode", "Forms")
    $formsEl = $authEl.SelectSingleNode("forms")
    if (-not $formsEl) {
        $formsEl = $webXml.CreateElement("forms")
        $authEl.AppendChild($formsEl) | Out-Null
    }
    $formsEl.SetAttribute("loginUrl", "logon.aspx")
    $formsEl.SetAttribute("name",     "sqlAuthCookie")
    $formsEl.SetAttribute("timeout",  "60")
    $formsEl.SetAttribute("path",     "/")
}

# 4b. identity impersonate="false"
$identEl = $sysWeb.identity
if ($identEl) { $identEl.SetAttribute("impersonate", "false") }

# 4c. <authorization><deny users="?" /></authorization>
$authzEl = $sysWeb.SelectSingleNode("authorization")
if (-not $authzEl) {
    $authzEl = $webXml.CreateElement("authorization")
    $sysWeb.AppendChild($authzEl) | Out-Null
}
$denyEl = $authzEl.SelectSingleNode("deny[@users='?']")
if (-not $denyEl) {
    $denyEl = $webXml.CreateElement("deny")
    $denyEl.SetAttribute("users", "?")
    $authzEl.AppendChild($denyEl) | Out-Null
}

# 4d. <machineKey> in <system.web> (must match rsreportserver.config)
$mkWeb = $sysWeb.SelectSingleNode("machineKey")
if (-not $mkWeb) {
    $mkWeb = $webXml.CreateElement("machineKey")
    $sysWeb.AppendChild($mkWeb) | Out-Null
}
$mkWeb.SetAttribute("validationKey", $validationKey)
$mkWeb.SetAttribute("decryptionKey", $decryptionKey)
$mkWeb.SetAttribute("validation",    "AES")
$mkWeb.SetAttribute("decryption",    "AES")

$webXml.Save($webConfig)
Write-Host "[CustomAuth] web.config updated."

# ── 5. Patch Portal Microsoft.ReportingServices.Portal.WebHost.exe.config ─────
$portalConfig = Join-Path $portal "Microsoft.ReportingServices.Portal.WebHost.exe.config"
if (Test-Path $portalConfig) {
    Write-Host "[CustomAuth] Patching $portalConfig"
    [xml]$pXml = Get-Content -Raw $portalConfig

    $pSysWeb = $pXml.configuration.SelectSingleNode("system.web")
    if (-not $pSysWeb) {
        $pSysWeb = $pXml.CreateElement("system.web")
        $pXml.configuration.AppendChild($pSysWeb) | Out-Null
    }
    $pMk = $pSysWeb.SelectSingleNode("machineKey")
    if (-not $pMk) {
        $pMk = $pXml.CreateElement("machineKey")
        $pSysWeb.AppendChild($pMk) | Out-Null
    }
    $pMk.SetAttribute("validationKey", $validationKey)
    $pMk.SetAttribute("decryptionKey", $decryptionKey)
    $pMk.SetAttribute("validation",    "AES")
    $pMk.SetAttribute("decryption",    "AES")

    $pXml.Save($portalConfig)
    Write-Host "[CustomAuth] Portal WebHost.exe.config updated."
} else {
    Write-Warning "[CustomAuth] Portal config not found at $portalConfig — skipping."
}

# ── 6. Create logon.aspx ──────────────────────────────────────────────────────
$logonAspx = Join-Path $pbirs "logon.aspx"
Write-Host "[CustomAuth] Creating $logonAspx"

$logonContent = @'
<%@ Page Language="C#" AutoEventWireup="true" %>
<%@ Import Namespace="System.Web.Security" %>
<script runat="server">
protected void Page_Load(object sender, EventArgs e)
{
    // If already authenticated via FormsAuth ticket, redirect immediately
    if (User.Identity.IsAuthenticated)
    {
        string ret = Request.QueryString["ReturnUrl"];
        if (string.IsNullOrEmpty(ret)) ret = "/Reports";
        Response.Redirect(ret, true);
        return;
    }

    // Translate loggedInUser cookie → FormsAuth ticket
    HttpCookie c = Request.Cookies["loggedInUser"];
    if (c != null && !string.IsNullOrEmpty(c.Value))
    {
        string val = Server.UrlDecode(c.Value);
        int sep = val.IndexOf(':');
        string user = sep > 0 ? val.Substring(0, sep).Trim() : val.Trim();
        if (!string.IsNullOrEmpty(user))
        {
            FormsAuthentication.SetAuthCookie(user, true);
            string ret = Request.QueryString["ReturnUrl"];
            if (string.IsNullOrEmpty(ret)) ret = "/Reports";
            Response.Redirect(ret, true);
            return;
        }
    }
    Response.StatusCode = 401;
    Response.Write("No loggedInUser cookie present. Set cookie loggedInUser=YourUsername and refresh.");
    Response.End();
}
</script>
'@

Set-Content -Path $logonAspx -Value $logonContent -Encoding UTF8
Write-Host "[CustomAuth] logon.aspx created."

Write-Host "[CustomAuth] Installation complete."
