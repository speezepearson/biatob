User stories
============

Two kinds of people interact with this system:
- "Authors," who want to offer bets on their claims, in order to signal credibility / win money from their readers / force themselves to operationalize their beliefs.
- "Readers," who might want to take those bets. There are several subcategories of reader:
    - Ones who **have never signed up** for the system.
    - Ones who **are averse** to the system and want to not see reminders of it.
    - Ones who **have signed up** for the system, and **have reciprocated trust** in the author they're reading.
    - Ones who **have signed up** for the system, but **aren't trusted** by the author they're reading.
    - Ones who **have signed up** for the system, but **don't trust** the author they're reading.



Author
------

I'm an author, writing about COVID-19. "B117 is going to be an enormous catastrophe," I write. Then I realize that I could pretty easily operationalize this belief. into something like "By 2021-08-01, at least 50% of U.S. COVID-19 cases will be B117 or a derivative strain, as reported by the CDC."

I go to `biatob.com/new` and fill in this form:

<iframe style="margin: 2em" width="100%" height="500" src="author-10-create.html"></iframe>

I click Create and I'm redirected to `biatob.com/bet/12345`:

<iframe style="margin: 2em" width="100%" height="500" src="author-20-created.html"></iframe>

I paste some of that HTML into my writing.

When 2020-08-01 rolls around, I get an email, reminding me to resolve this wager. I visit the page and click the "Resolve YES" button.

I get... one email telling me how much I owe / am owed by each participant? One email per participant, with them CCed, so that I can view the emails as a to-do list? Maybe this is configurable.



Reader
------

### Reciprocally trusting reader

I'm reading my friend's writing, when I see:
<svg height=1.5ex viewBox="0 0 100 15"><style>a { fill: #008800 }</style><a href="http://example.com/TODO" x=0 y=13><text text-decoration="underline" x=0 y=13>$100 @ 80-90%</text></a></svg>. I click it. I'm directed, of course, to `biatob.com/bet/12345`:

<iframe style="margin: 2em" width="100%" height="500" src="trusted-10-fresh.html"></iframe>

I think my friend's overly worried, so I click the second Commit button. The page reloads.
<iframe style="margin: 2em" width="100%" height="500" src="trusted-20-postbet.html"></iframe>

I check back in a couple weeks, after the market closes. The page now reads:

<iframe style="margin: 2em" width="100%" height="500" src="trusted-30-closed.html"></iframe>

At some point, my friend resolves the market Yes. Then the page looks like:

<iframe style="margin: 2em" width="100%" height="500" src="trusted-40-resolved.html"></iframe>

I also receive an email


### Newbie reader

I'm reading somebody's writing, when I see <svg height=1.5ex viewBox="0 0 100 15"><style>a { fill: #008800 }</style><a href="http://example.com/TODO" x=0 y=13><text text-decoration="underline" x=0 y=13>$100 @ 80-90%</text></a></svg>. I click it out of curiosity. It shows:

<iframe style="margin: 2em" width="100%" height="500" src="newbie-1.html"></iframe>


### Untrusted reader

I'm reading something written by somebody I idolize but who doesn't know I exist. I see <svg height=1.5ex viewBox="0 0 100 15"><style>a { fill: #008800 }</style><a href="http://example.com/TODO" x=0 y=13><text text-decoration="underline" x=0 y=13>$100 @ 80-90%</text></a></svg>. I click it, and see:

<div style="margin: 1em; border: 1px solid black; padding: 2em">
  <h2>By 2021-08-01, will at least 50% of U.S. COVID-19 cases be B117 or a derivative strain, as reported by the CDC?</h2>
  Spencer assigned this a 80-90% chance, and staked $100. <br />
  <div style="margin: 1em; border: 1px solid black; padding: 1em">
    <p><code>spencer@invalid.net</code> hasn't marked you as trusted. If you think this is a mistake, reach out to him, linking him to http://biatob.com/user/bobthereader@example.com (<button>Copy</button>), and asking him to mark you as trusted.</p>
  </div>
  Market opened 2021-01-09, closes 2021-01-23. <br />
  Stake $<input disabled style="width: 5em" type="number" value="99" step="1" /> against Spencer's <strong>$11</strong> that this will resolve Yes? <button disabled>Commit</button><br />
  Stake $<input disabled style="width: 5em" type="number" value="25" step="1" /> against Spencer's <strong>$100</strong> that this will resolve No? <button disabled>Commit</button><br />
  <strong>Spencer's special rules:</strong> If the CDC doesn't publish statistics on this, I'll fall back to some other official organization, like the WHO; failing that, I'll look for journal papers on U.S. cases, and go with a consensus if I find one; failing that, the market is unresolvable. <br/>
</div>


### Untrusting reader

<div style="margin: 1em; border: 1px solid black; padding: 2em">
  <h2>By 2021-08-01, will at least 50% of U.S. COVID-19 cases be B117 or a derivative strain, as reported by the CDC?</h2>
  Spencer assigned this a 80-90% chance, and staked $100. <br />
  <div style="margin: 1em; border: 1px solid black; padding: 1em">
    <p>It looks like you haven't marked <code>spencer@invalid.net</code> as trusted, so, for your own protection, I'm not letting you bet against him. <button>Mark spencer@invalid.net as trusted</button>?</p>
  </div>
  Market opened 2021-01-09, closes 2021-01-23. <br />
  Stake $<input disabled style="width: 5em" type="number" value="99" step="1" /> against Spencer's <strong>$11</strong> that this will resolve Yes? <button disabled>Commit</button><br />
  Stake $<input disabled style="width: 5em" type="number" value="25" step="1" /> against Spencer's <strong>$100</strong> that this will resolve No? <button disabled>Commit</button><br />
  <strong>Spencer's special rules:</strong> If the CDC doesn't publish statistics on this, I'll fall back to some other official organization, like the WHO; failing that, I'll look for journal papers on U.S. cases, and go with a consensus if I find one; failing that, the market is unresolvable. <br/>
</div>
