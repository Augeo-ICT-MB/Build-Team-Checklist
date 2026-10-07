// Supabase connection for the Cvent QC Checklist.
// Find both values in Supabase: Project Settings > API (Data API).
// The anon (public) key is designed to be visible in a website; the database
// access rules in supabase/schema.sql are what keep the data private.
// NEVER put the service_role key here.
//
// Leave these as-is to run the checklist in browser-only mode (no sign-in,
// progress saved per browser).
window.QC_CONFIG = {
  supabaseUrl: "https://ehxjgruvqurtentztnlw.supabase.co",
  supabaseAnonKey: "sb_publishable_-0KyjWvVqdDKZqbyuWYVRQ_04gRfpaG",

  // false = only people you invite in Supabase can sign in (recommended).
  allowSignups: false
};
