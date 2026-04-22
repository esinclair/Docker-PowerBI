using System.Security;
using System.Security.Principal;

namespace PowerBI.CustomAuth
{
    /// <summary>
    /// Represents an identity authenticated via the "loggedInUser" cookie.
    /// </summary>
    [SecurityCritical]
    public class CookieIdentity : IIdentity
    {
        public CookieIdentity(string name, bool isAuthenticated)
        {
            Name = name ?? string.Empty;
            IsAuthenticated = isAuthenticated;
        }

        public string Name { get; }
        // "Forms" matches the extension Name="Forms" in rsreportserver.config.
        // PBIRS looks up the auth extension by AuthenticationType; returning "Cookie"
        // would make it look for a "Cookie" extension (not found → NullRef in policy timer).
        // Unauthenticated identities must return "" per the IIdentity contract.
        public string AuthenticationType => IsAuthenticated ? "Forms" : string.Empty;
        public bool IsAuthenticated { get; }
    }
}
