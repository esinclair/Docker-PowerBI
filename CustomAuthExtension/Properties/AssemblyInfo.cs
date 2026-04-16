using System.Security;

// Required for PBIRS extensions running under Code Access Security (legacyCasModel).
// Level1 opts into legacy CAS transparency so that overriding interface members
// from Microsoft.ReportingServices.Interfaces does not trigger TypeLoadException
// ("Inheritance security rules violated while overriding member").
[assembly: AllowPartiallyTrustedCallers]
[assembly: SecurityRules(SecurityRuleSet.Level1)]
