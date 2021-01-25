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

<div style="margin: 1em; border: 1px solid black; padding: 2em">
  What question are you willing to stake money on? (<a href="http://example.com/TODO">how to write good bets</a>) <br/>
  <textarea style="width:30em">By 2021-08-01, will at least 50% of U.S. COVID-19 cases be B117 or a derivative strain, as reported by the CDC?</textarea><br />
  How sure are you that the answer will be "yes"? <input style="width:3em" type="number" min=0 max=100 step="any" value=80 />-<input style="width:3em" type="number" min=0 max=100 step="any" value=90 />% <br />
  How much are you willing to stake? $<input type="number" value="100"/> <br />
  How long is this offer open for? <input style="width:4em" type="number" value="2" min=0 step=1 /> <select><option>weeks</option><option>days</option></select><br />
  Any special rules? (For instance: what might make you consider the market unresolvable/invalid? What would you count as "insider trading"/cheating?)<br />
  <textarea style="width:30em">If the CDC doesn't publish statistics on this, I'll fall back to some other official organization, like the WHO; failing that, I'll look for journal papers on U.S. cases, and go with a consensus if I find one; failing that, the market is unresolvable.</textarea><br />
  <button>Create</button><br />
  <hr />
  Preview:
  <div style="margin: 1em; border: 1px solid black; padding: 2em">
    <h2>By 2021-08-01, will at least 50% of U.S. COVID-19 cases be B117 or a derivative strain, as reported by the CDC?</h2>
    Spencer assigned this a 80-90% chance, and staked $100. <br />
    Market opened 2021-01-09, closes 2021-01-23. <br />
    Stake $<input style="width: 5em" type="number" value="99" step="1" /> against Spencer's <strong>$11</strong> that this will resolve Yes? <button>Commit</button><br />
    Stake $<input style="width: 5em" type="number" value="25" step="1" /> against Spencer's <strong>$100</strong> that this will resolve No? <button>Commit</button><br />
    <strong>Spencer's special rules:</strong> If the CDC doesn't publish statistics on this, I'll fall back to some other official organization, like the WHO; failing that, I'll look for journal papers on U.S. cases, and go with a consensus if I find one; failing that, the market is unresolvable. <br/>
    </div>

</div>

I click Create and I'm redirected to `biatob.com/bet/12345`:

<div style="margin: 1em; border: 1px solid black; padding: 2em">
  <h2>By 2021-08-01, will at least 50% of U.S. COVID-19 cases be B117 or a derivative strain, as reported by the CDC?</h2>
  Spencer assigned this a 80-90% chance, and staked $100. <br />
  Market opened 2021-01-09, closes 2021-01-23. <br />
  Stake $<input style="width: 5em" type="number" value="99" step="1" /> against Spencer's <strong>$11</strong> that this will resolve Yes? <button>Commit</button><br />
  Stake $<input style="width: 5em" type="number" value="25" step="1" /> against Spencer's <strong>$100</strong> that this will resolve No? <button>Commit</button><br />
  <strong>Spencer's special rules:</strong> If the CDC doesn't publish statistics on this, I'll fall back to some other official organization, like the WHO; failing that, I'll look for journal papers on U.S. cases, and go with a consensus if I find one; failing that, the market is unresolvable. <br/>
  <hr />
  As the creator of this market, you might want to link to it in your writing! Here are some snippets of HTML you could copy-paste.
  <ul>
    </li>
    <li>
      A linked inline image: <br />
      <code>&lt;a href="https://biatob.com/bet/12345&gt;&lt;img style="max-height:1.5ex" src="https://biatob.com/bet/12345/ref.png?fg=000000" /&gt;&lt;/a&gt;</code> <button>Copy</button> <br />
      Or SVG: <br />
      <code>&lt;svg&gt;&lt;style&gt;a{fill:#008800;}&lt;/style&gt;&lt;use xlink:href="https://biatob.com/bet/12345/ref.svg"&gt;&lt;/use&gt;&lt;/svg&gt;</code> <button>Copy</button> <br />
      <details>
        <summary>Styling<summary>
        Foreground color: <input type="color" value="#008800" /><br />
      </details>
      In your writing, this would look like "<svg height=1.5ex viewBox="0 0 100 15"><style>a { fill: #008800 }</style><a href="http://example.com/TODO" x=0 y=13><text text-decoration="underline" x=0 y=13>$100 @ 80-90%</text></a></svg>".
    </li>
    <li>A boring old link: <br/>
      <code>&lt;a style="max-height:1.5ex" href="https://biatob.com/bet/12345&gt;[stake $20, 50-60%]&lt;/a&gt;</code><br/>
      In your writing, this would look like "<a>[stake $20, 50-60%]</a>"
    </li>
  </ul>
</div>

I paste some of that HTML into my writing.

Reader
------

### Reciprocally trusting reader

I'm reading my friend's writing, when I see:
<svg height=1.5ex viewBox="0 0 100 15"><style>a { fill: #008800 }</style><a href="http://example.com/TODO" x=0 y=13><text text-decoration="underline" x=0 y=13>$100 @ 80-90%</text></a></svg>. I click it. I'm directed, of course, to `biatob.com/bet/12345`:

<div style="margin: 1em; border: 1px solid black; padding: 2em">
  <h2>By 2021-08-01, will at least 50% of U.S. COVID-19 cases be B117 or a derivative strain, as reported by the CDC?</h2>
  Spencer assigned this a 80-90% chance, and staked $100. <br />
  Market opened 2021-01-09, closes 2021-01-23. <br />
  Stake $<input style="width: 5em" type="number" value="99" step="1" /> against Spencer's <strong>$11</strong> that this will resolve Yes? <button>Commit</button><br />
  Stake $<input style="width: 5em" type="number" value="25" step="1" /> against Spencer's <strong>$100</strong> that this will resolve No? <button>Commit</button><br />
  <strong>Spencer's special rules:</strong> If the CDC doesn't publish statistics on this, I'll fall back to some other official organization, like the WHO; failing that, I'll look for journal papers on U.S. cases, and go with a consensus if I find one; failing that, the market is unresolvable. <br/>
</div>

I think my friend's overly worried, so I click the second Commit button. The page reloads.

<div style="margin: 1em; border: 1px solid black; padding: 2em">
  <h2>By 2021-08-01, will at least 50% of U.S. COVID-19 cases be B117 or a derivative strain, as reported by the CDC?</h2>
  Spencer assigned this a 80-90% chance, and staked $100. <br />
  Market opened 2021-01-09, closes 2021-01-23. <br />
  Stake $<input style="width: 5em" type="number" value="99" step="1" /> against Spencer's <strong>$11</strong> that this will resolve Yes? <button>Commit</button><br />
  Stake $<input disabled style="width: 5em" type="number" value="0" step="1" /> against Spencer's <strong>$0</strong> that this will resolve No? <button disabled>Commit</button><br />
  <strong>Spencer's special rules:</strong> If the CDC doesn't publish statistics on this, I'll fall back to some other official organization, like the WHO; failing that, I'll look for journal papers on U.S. cases, and go with a consensus if I find one; failing that, the market is unresolvable. <br/>
  <strong>Your stake:</strong> if the market resolves Yes, you owe Spencer $25; if No, Spencer owes you $100.
</div>

I check back in a couple weeks, after the market closes. The page now reads:

<div style="margin: 1em; border: 1px solid black; padding: 2em">
  <h2>By 2021-08-01, will at least 50% of U.S. COVID-19 cases be B117 or a derivative strain, as reported by the CDC?</h2>
  Spencer assigned this a 80-90% chance, and staked $100. <br />
  Market opened 2021-01-09, closed 2021-01-23. <br />
  <strong>Spencer's special rules:</strong> If the CDC doesn't publish statistics on this, I'll fall back to some other official organization, like the WHO; failing that, I'll look for journal papers on U.S. cases, and go with a consensus if I find one; failing that, the market is unresolvable. <br/>
  <strong>Your stake:</strong> if the market resolves Yes, you owe Spencer $25; if No, Spencer owes you $100.
</div>

At some point, my friend resolves the market Yes. Then the page looks like:

<div style="margin: 1em; border: 1px solid black; padding: 2em">
  <h2>By 2021-08-01, will at least 50% of U.S. COVID-19 cases be B117 or a derivative strain, as reported by the CDC?</h2>
  <span style="color:red">You owe Spencer $25, which you staked against his $100.</span> <br />
  Spencer assigned this a 80-90% chance, and staked $100. <br />
  Market opened 2021-01-09, closed 2021-01-23. <br />
  <strong>Spencer's special rules:</strong> If the CDC doesn't publish statistics on this, I'll fall back to some other official organization, like the WHO; failing that, I'll look for journal papers on U.S. cases, and go with a consensus if I find one; failing that, the market is unresolvable. <br/>
</div>

### Newbie reader

I'm reading somebody's writing, when I see <svg height=1.5ex viewBox="0 0 100 15"><style>a { fill: #008800 }</style><a href="http://example.com/TODO" x=0 y=13><text text-decoration="underline" x=0 y=13>$100 @ 80-90%</text></a></svg>. I click it out of curiosity. It shows:

<div style="margin: 1em; border: 1px solid black; padding: 2em">
  <h2>By 2021-08-01, will at least 50% of U.S. COVID-19 cases be B117 or a derivative strain, as reported by the CDC?</h2>
  Spencer assigned this a 80-90% chance, and staked $100. <br />
  <div style="margin: 1em; border: 1px solid black; padding: 1em">
    <p>Hi, newcomer! Confused? Curious?  This is a site that helps people make friendly wagers! <span style="opacity:0.5">("Why?" To promote epistemic virtue and thereby make the world a better, saner place! When I force myself to make concrete predictions about important things, it frequently turns out that I don't actually believe what I thought I did. (Crazy, right!? Brains <i>suck!</i>) And betting, i.e. attaching money to my predictions, is <a href="https://marginalrevolution.com/marginalrevolution/2012/11/a-bet-is-a-tax-on-bullshit.html">just an extra incentive to get them right</a>.)</span></p>
    <p>Spencer is willing to put his money where his mouth is. Good for him! And, if you think he's wrong, you can earn money and set him straight at the same time!</p>
    <details><summary><strong>"Cool! How do I accept this bet?"</strong></summary>
        <p> First off, let's be clear: this is not a "real" prediction market site like PredictIt or Betfair. Everything here works on the honor system. A bet can only be made between <i>people who trust each other in real life.</i> So, ask yourself, do you trust Spencer? And does Spencer trust you? If either answer is no, you're out of luck: the honor system only works where there's honor.</p>
        <p>But! If you do trust each other, the flow goes like this:</p>
        <ul>
          <li><input type="email" placeholder="email@ddre.ss"/> <input type="password" placeholder="password"/> <select><option>they/them</option><option>she/her</option><option>he/him</option></select><button>Sign up</button></li>
          <li><button disabled>Mark spencer@invalid.net as trusted</button></li>
          <li>Ask Spencer to go to <code>https://biatob.com/user/__YOUR_EMAIL__</code> and mark <i>you</i> as trusted. <button disabled>Copy</button></li>
          <li>Wager against him, below!</li>
        </ul>
        <p>When the bet resolves, you'll both get an email telling you who owes who how much. You can enter that into Venmo or Splitwise or whatever.</p>
        <p><button>Hide this tutorial.</button></p>
      </details>
      <details><summary><strong>"I <i>really</i> don't like this idea."</strong></summary> Sorry! I know some people are averse to this sort of thing. If you click <button>Hide embeds</button>, I'll try to not show you any more links to people's wagers (insofar as I can -- it's hard to control what appears on other people's sites).
      </details>
  </div>
  Market opened 2021-01-09, closes 2021-01-23. <br />
  Stake $<input disabled style="width: 5em" type="number" value="99" step="1" /> against Spencer's <strong>$11</strong> that this will resolve Yes? <button disabled>Commit</button><br />
  Stake $<input disabled style="width: 5em" type="number" value="25" step="1" /> against Spencer's <strong>$100</strong> that this will resolve No? <button disabled>Commit</button><br />
  <strong>Spencer's special rules:</strong> If the CDC doesn't publish statistics on this, I'll fall back to some other official organization, like the WHO; failing that, I'll look for journal papers on U.S. cases, and go with a consensus if I find one; failing that, the market is unresolvable. <br/>
</div>


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
