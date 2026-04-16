using System;
using System.Security;
using System.Security.Principal;
using System.Web;
using Microsoft.ReportingServices.Interfaces;

namespace PowerBI.CustomAuth
{
    /// <summary>
    /// PBIRS custom authentication extension.
    /// Reads the "loggedInUser" cookie and returns the authenticated identity.
    /// Cookie format: "Username" or "Username:anything" (text after ':' is ignored).
    /// </summary>
    [SecurityCritical]
    public class CookieAuthExtension : IAuthenticationExtension2, IExtension
    {
        private const string CookieName = "loggedInUser";

        public string LocalizedName => "Cookie Authentication";

        public void SetConfiguration(string configuration) { }

        // ── ReportServer (ASP.NET) path ──────────────────────────────────────────

        public void GetUserInfo(out IIdentity userIdentity, out IntPtr userId)
        {
            userId = IntPtr.Zero;
            userIdentity = null;

            try
            {
                var ctx = HttpContext.Current;

                // FormsAuth ticket already decoded by ASP.NET pipeline (via logon.aspx)
                if (ctx?.User?.Identity != null && ctx.User.Identity.IsAuthenticated)
                {
                    userIdentity = new CookieIdentity(ctx.User.Identity.Name, true);
                    return;
                }

                // Fallback: read loggedInUser cookie directly
                string user = ParseUsername(ctx?.Request?.Cookies[CookieName]?.Value);
                if (user != null)
                {
                    userIdentity = new CookieIdentity(user, true);
                    return;
                }
            }
            catch { }

            if (userIdentity == null)
                userIdentity = new CookieIdentity(string.Empty, false);
        }

        // ── Portal (WebHost) path ────────────────────────────────────────────────

        public void GetUserInfo(IRSRequestContext requestContext,
                                out IIdentity userIdentity, out IntPtr userId)
        {
            userId = IntPtr.Zero;
            userIdentity = null;

            try
            {
                // 1. FormsAuth identity forwarded by Portal
                if (requestContext?.User != null && requestContext.User.IsAuthenticated)
                {
                    userIdentity = new CookieIdentity(requestContext.User.Name, true);
                    return;
                }

                // 2. loggedInUser cookie via PassThroughCookies
                if (requestContext?.Cookies != null)
                {
                    string val;
                    if (requestContext.Cookies.TryGetValue(CookieName, out val))
                    {
                        string user = ParseUsername(val);
                        if (user != null)
                        {
                            userIdentity = new CookieIdentity(user, true);
                            return;
                        }
                    }
                }

                // 3. Fallback: ASP.NET HttpContext (direct requests)
                var ctx = HttpContext.Current;
                if (ctx?.User?.Identity != null && ctx.User.Identity.IsAuthenticated)
                {
                    userIdentity = new CookieIdentity(ctx.User.Identity.Name, true);
                    return;
                }

                string u = ParseUsername(ctx?.Request?.Cookies[CookieName]?.Value);
                if (u != null)
                {
                    userIdentity = new CookieIdentity(u, true);
                    return;
                }
            }
            catch { }

            if (userIdentity == null)
                userIdentity = new CookieIdentity(string.Empty, false);
        }

        /// <summary>
        /// Called by PBIRS when FormsAuth posts credentials.
        /// We accept any non-empty username — the real auth is the cookie.
        /// </summary>
        public bool LogonUser(string userName, string password, string authority)
            => !string.IsNullOrWhiteSpace(userName);

        public bool IsValidPrincipalName(string principalName)
            => !string.IsNullOrWhiteSpace(principalName);

        // ── Helper ───────────────────────────────────────────────────────────────

        /// <summary>
        /// Extracts the username from a cookie value.
        /// Accepts "Username" or "Username:anything".
        /// </summary>
        internal static string ParseUsername(string cookieValue)
        {
            if (string.IsNullOrWhiteSpace(cookieValue))
                return null;
            int sep = cookieValue.IndexOf(':');
            string name = (sep >= 0 ? cookieValue.Substring(0, sep) : cookieValue).Trim();
            return name.Length > 0 ? name : null;
        }
    }
}
