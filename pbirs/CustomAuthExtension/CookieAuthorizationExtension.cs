using System;
using System.Collections.Specialized;
using System.IO;
using System.Runtime.Serialization.Formatters.Binary;
using System.Security;
using Microsoft.ReportingServices.Interfaces;

namespace PowerBI.CustomAuth
{
    /// <summary>
    /// PBIRS custom authorization extension.
    /// Grants full access to every authenticated user (non-empty userName).
    /// </summary>
    [SecurityCritical]
    public class CookieAuthorizationExtension : IAuthorizationExtension, IExtension
    {
        public string LocalizedName => "Cookie Authorization";

        public void SetConfiguration(string configuration) { }

        // ── CheckAccess: grant everything to any authenticated user ──────────────

        private static bool IsAuthenticated(string userName)
            => !string.IsNullOrEmpty(userName);

        public byte[] CreateSecurityDescriptor(
            AceCollection acl,
            SecurityItemType itemType,
            out string stringSecDesc)
        {
            stringSecDesc = null;
            if (acl == null) return new byte[0];

            var bf = new BinaryFormatter();
            using (var ms = new MemoryStream())
            {
                bf.Serialize(ms, acl);
                return ms.ToArray();
            }
        }

        public bool CheckAccess(string userName, IntPtr userToken,
            byte[] secDesc, CatalogOperation requiredOperation)
            => IsAuthenticated(userName);

        public bool CheckAccess(string userName, IntPtr userToken,
            byte[] secDesc, CatalogOperation[] requiredOperations)
            => IsAuthenticated(userName);

        public bool CheckAccess(string userName, IntPtr userToken,
            byte[] secDesc, ReportOperation requiredOperation)
            => IsAuthenticated(userName);

        public bool CheckAccess(string userName, IntPtr userToken,
            byte[] secDesc, FolderOperation requiredOperation)
            => IsAuthenticated(userName);

        public bool CheckAccess(string userName, IntPtr userToken,
            byte[] secDesc, FolderOperation[] requiredOperations)
            => IsAuthenticated(userName);

        public bool CheckAccess(string userName, IntPtr userToken,
            byte[] secDesc, ResourceOperation requiredOperation)
            => IsAuthenticated(userName);

        public bool CheckAccess(string userName, IntPtr userToken,
            byte[] secDesc, ResourceOperation[] requiredOperations)
            => IsAuthenticated(userName);

        public bool CheckAccess(string userName, IntPtr userToken,
            byte[] secDesc, DatasourceOperation requiredOperation)
            => IsAuthenticated(userName);

        public bool CheckAccess(string userName, IntPtr userToken,
            byte[] secDesc, ModelOperation requiredOperation)
            => IsAuthenticated(userName);

        public bool CheckAccess(string userName, IntPtr userToken,
            byte[] secDesc, ModelItemOperation requiredOperation)
            => IsAuthenticated(userName);

        public StringCollection GetPermissions(string userName, IntPtr userToken,
            SecurityItemType itemType, byte[] secDesc)
        {
            var perms = new StringCollection();
            if (IsAuthenticated(userName))
                perms.Add("Content Manager");
            return perms;
        }
    }
}
