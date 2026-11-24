# Help screenshots

> OPS-06. The pictures in the help articles are photographed from the demo data, so they can
> be retaken whenever a screen changes. This page covers what to do when CI says a picture is
> out of date, and how to take new ones, with or without anything set up on your computer.

## When the check fails

CI's **Tests** job has a step called **Help screenshots are current**. It fails when a screen
shown in a help article has changed since its picture was taken. The PR is fine otherwise; the
pictures just need retaking so the articles match the app.

Open the failed step's log. Each out-of-date picture has a line like this:

```
Help screenshot send-quote-page (in send-a-quote) shows a screen that has changed since it was captured on 2026-11-24.
```

- `send-quote-page` is the picture.
- `(in send-a-quote)` is the article that shows it: `content/help/articles/send-a-quote.md`.
- "hasn't been captured" means a new picture that was never taken.
- "is recorded but no article declares it" means a picture was removed from an article. Retaking
  pictures tidies this up.

The last line says what to do next: retake the pictures (Option A or B below), then re-read the
articles listed.

## Option A: let CI take them (nothing to set up)

1. On the pull request, add the label **help screenshots**. It never runs on `main`. (Or, once this workflow is on
   `main`: open **Actions** → **Help screenshots** → **Run workflow**, choose the branch, and
   tick **all** to retake every picture, for example after a restyle.)
2. Wait for the **Capture help screenshots** run to finish, about five minutes. It commits the
   new pictures to the branch as "OPS-06: capture help screenshots".
3. Look at the new pictures in the PR's **Files changed** tab. They should show the demo
   business (Oakline Lawn & Landscape, or Rivera Pest Control for a new business) and nothing
   else.
4. That commit doesn't start CI by itself (GitHub's rule for commits made by a workflow). Push
   your next change, such as the article updates below, or re-run CI from the PR's
   **Checks** tab.

To run it again on the same PR, remove the label and add it again.

## Option B: take them on your computer

You need:

- the app set up as usual (`bin/setup --skip-server`, PostgreSQL running);
- Chrome or Chromium installed. If it isn't found, set `BROWSER_PATH` to it, such as
  `BROWSER_PATH=/opt/google/chrome/chrome`;
- libvips (`brew install vips` on a Mac, `apt install libvips42` on Ubuntu).

Then, from the app's folder:

```sh
bin/help-screenshots          # retake the pictures that changed, and take new ones
bin/help-screenshots --all    # retake every picture
bin/help-screenshots --check  # what CI runs: says which are out of date, changes nothing
```

It uses its own database, `shadetree_test_help`. If `DATABASE_URL` is set, it uses the database
that names with `_help` added to its name (`postgres:///x?application_name=dev` becomes
`x_help`), or `HELP_DATABASE_URL` if you set it, whose name must end in `_help`. It refuses
anything else before dropping anything. The database is wiped and filled with the demo data on
every run, so it never touches your development data. It writes the pictures to
`app/assets/images/help/` and their records to `content/help/screenshots.yml`. Commit both.

## Other company names in articles

Articles don't name other companies' products, in their words or their pictures' alt text. Say
what a thing does instead ("your card payment provider"). The Tests job fails with a line like
"take-card-payments: names Stripe; say what it does instead". The pictures themselves may show
the app's own wording, names included.

## Then re-read the articles

A new picture can mean the steps changed too. For each article named in the check's message:

1. Open it in `content/help/articles/` and read it next to the new pictures.
2. Fix anything that no longer matches: button labels, the order of steps, what happens next.
3. Set `reviewed:` in its front matter to today's date.

CI checks this. If an article's `reviewed` date is older than its pictures, the Tests job fails
with a line like "send-a-quote: its screenshots were captured on 2026-11-24; re-read it and set
reviewed to that date or later". This lists exactly the articles whose pictures you retook.

## After a redesign

When a restyle changes every screen (#438, for example), every picture changes at once.

**The check won't always tell you.** It compares each screen's HTML, not how it looks. A
redesign that only changes colors, fonts or spacing (the CSS) leaves the HTML as it was, so the
check stays green while every picture is out of date. After any visual change, retake the
pictures yourself, even when CI is green.

1. Retake them all: Option A with **all** ticked, or `bin/help-screenshots --all`.
2. Every article with pictures needs re-reading. The Tests job lists each one; work through the
   list, then set each `reviewed:` date.
3. If a page moved or a button was renamed, update the article's steps. If a picture's region no
   longer exists (the capture stops with "no … at /admin/…"), change that screenshot's `region:`
   (or `path:`) in the article's front matter.
4. Push once everything is updated, and check that CI is green.

## If the capture stops

- "… went to /users/sign_in": the demo user couldn't open the page. Check the screenshot's `as:`
  (owner, admin, technician, or new for the owner of the new, empty demo business) has access to
  it.
- "answered 404": a demo record in the path wasn't found. Check the name given for it (for
  example `quote: Spring cleanup`) against `db/seeds/development.rb`.
