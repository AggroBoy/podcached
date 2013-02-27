## podcached

The name is the best thing about this tool.

It's a simple ruby program that maintains a local mirror of a set of
podcasts. That just means downloading enclosures, and keeping a modified
local copy of the feed, pointing at the locally mirrored data.

It's not super-clever or very efficient, but it does the job.

It doesn't have a daemon mode; run it using cron.

It doesn't serve pages; point apache at its output directory.
