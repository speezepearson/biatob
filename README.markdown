This is a harebrained idea for a project to glorify betting. It provides a mechanism for writers to include little tags in their writing that indicate a willingness to bet on their claims.

This project is not going to touch real money, for several reasons: financial stuff is really hard; good security is really hard; and it would probably be illegal. So, it's targeted at people who want to make bets _with their friends,_ or people they trust, at least. Everything is purely honor-system.

TODO:
- sketch the signup process, and how trust is establihed between accounts
- write copy explaining how to operationalize a bet well
- consider a semi-formalized system for naming an arbiter.


Writer
======

As a writer, I go to `biatob.com/new` and see something like

<div style="margin: 1em; border: 1px solid black; padding: 2em">
  Question: <textarea style="width:30em" placeholder="Will the cat barf on the rug in January 1962?"></textarea><br />
  Max exposure: <input type="number" value="20"/> <br />
  Price of "IOU $1 if yes": <input type="number" min=0 max=1 step="any" value=0.50 /> <br />
  Price of "IOU $1 if no": <input type="number" min=0 max=1 step="any" value=0.60 /> <br />
  Who can participate? <select><option>default</option></select><br />
  How long is this offer open for? Until EOD <input type="date" value="1961-12-31" /><br />
  When will you settle debts by? <input type="date" value="1962-01-31" /><br />
  What, if anything, might make you consider this market to be unresolvable, or trades to be "cheating"?<textarea style="width:30em" placeholder="If you see the cat barf on the rug, and then place a bet, that's cheating. If the cat dies before January, that invalidates the market."></textarea><br />
  <button>Create</button><br />
  <hr />
  Preview:
  <div style="margin: 1em; border: 1px solid black; padding: 2em">
    <h2>Will the cat barf on the rug in January 1962?</h2>
    Spencer assigns this a 50-60% chance. <br />
    Buy up to 20 "IOU $1 if yes" tickets, at $0.50 apiece? <input type="number" value="5" step="1" /><button>Buy</button><br />
    Buy up to 20 "IOU $1 if no" tickets, at $0.60 apiece? <input type="number" value="5" step="1" /><button>Buy</button><br />
    Offer open until EOD 1961-12-31. Spencer intends to settle debts by 1962-01-31.<br />
    Guidelines: If you see the cat barf on the rug, and then place a bet, that's cheating. If the cat dies before January, that invalidates the market.<br/>
    Participants: (none yet) <br />
  </div>

</div>

I click Create and I'm redirected to `biatob.com/bet/12345`:

<div style="margin: 1em; border: 1px solid black; padding: 2em">
  <h2>Will the cat barf on the rug in January 1962?</h2>
  Spencer assigns this a 50-60% chance. <br />
  Buy up to 20 "IOU $1 if yes" tickets, at $0.50 apiece? <input type="number" value="5" step="1" /><button>Buy</button><br />
  Buy up to 20 "IOU $1 if no" tickets, at $0.60 apiece? <input type="number" value="5" step="1" /><button>Buy</button><br />
  Offer open until EOD 1961-12-31. Spencer intends to settle debts by 1962-01-31.<br />
  Guidelines: If you see the cat barf on the rug, and then place a bet, that's cheating. If the cat dies before January, that invalidates the market.<br/>
  Participants: (none yet) <br/>
  <hr />
  As the creator of this market, you might want to link to it in your writing! Here are some snippets of HTML you could copy-paste.
  <ul>
    <li>
      A linked inline image:<br/>
      <code>&lt;a href="https://biatob.com/bet/12345&gt;&lt;img style="max-height:1.5ex" src="https://biatob.com/bet/12345/image-embed.png?fg=000000&bg=ffffff&untrustedDisplay=none" /&gt;&lt;/a&gt;</code><br/>
      <details>
        <summary><button>Copy</button><summary>
        Foreground color: <input type="color" value="#000000" /><br />
        Background color: <input type="color" value="#ffffff" /><br />
        Display for people you don't trust: <select type="checkbox"><option>none</option><option>% only</option><option>normal</option></select><br />
      </details>
      In your writing, this would look like "<img style="max-height: 1.5ex" src="data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAJgAAAARCAYAAAAhfWUxAAAABmJLR0QA/wD/AP+gvaeTAAAACXBIWXMAAAsTAAALEwEAmpwYAAAAB3RJTUUH5QEXBhwiTWkGDAAAAB1pVFh0Q29tbWVudAAAAAAAQ3JlYXRlZCB3aXRoIEdJTVBkLmUHAAABrElEQVRo3u1awbLDIAgEx///Zd/pdaijCLhG25pTawyuK+BiwqWUQvdqXsxMREQ9ipiZTqZvB76asywb60sj1trXCgg1pseeBTNigSQmzR6SVyS+nn+0nimlvPVPsw5hBWF9xtrWapfR8z/pnr3RwmnzYebXfflb6/c0r2h80bXN0WiRfWedy2prdsyZ5yyO0OOvjuqneEXh07LayGdSBHxtVMsW3pRc/0eNGQmkHhZ5T2bL1vOWsVbyisA3w2+OaIUVQE4SvR7NsWsun4CPmd8dbEcFYhXlJ1aXv4rPYz/V6RKhc9Ai3xu5UrzKtvq+V+T2tMgpDvc0PksyyL29f4UYHqVuWflEM1mP5FrP1M7m1WWtCnZHxm8dE+zENyXyV0fAJ535tkT0SVvnKnxeG/lbBPxuLblzGzwZR/LoIC39Rsr/nh3UmNGI9bxNQGQGFK+r8M3MK/SqCAna83pk5ZmXNftpQTHqazkKQmtfJL7IeVzSDuEQ7d6F95zhjAJAs9WqNGecdXbrQvC6El/UFt+vKeL67X5NMR43XTfCVk2XL36mirwV2+WMiOgPrf2gSoHBkWMAAAAASUVORK5CYII=" />" for people you trust, and "" for people you don't.
    </li>
    <li>A boring old link: <br/>
      <code>&lt;a style="max-height:1.5ex" href="https://biatob.com/bet/12345&gt;[stake $20, 50-60%]&lt;/a&gt;</code><br/>
      In your writing, this would look like "<a>[stake $20, 50-60%]</a>"
    </li>
  </ul>
</div>

I paste the HTML image code into my writing.

Untrusted reader
================

I'm reading somebody's writing. Depending on how the writer configured the market, either I see nothing special, or <img style="max-height: 1.5ex" src="data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAADcAAAANCAYAAAANOvaNAAAABmJLR0QA/wD/AP+gvaeTAAAACXBIWXMAAAsTAAALEwEAmpwYAAAAB3RJTUUH5QEXBwQmyd0wewAAAB1pVFh0Q29tbWVudAAAAAAAQ3JlYXRlZCB3aXRoIEdJTVBkLmUHAAAA00lEQVRIx71WWw6AIAyzhPtfuX5pFtwbIj8qrHUdYwwkCeDSBsn3XbOR695YsSsu4o7w0k6ujY5z0XxkI+ci7udJ8nXc4lxFz8pORDvpiahkQYY7E+SRBa7CvSh6wjRslTsKvLpznkPdcYrHC771j9kBdRz4U/BHnJbz1dyvFJSsQJIXADWrJI8WwGnlfEVYZLsbOC0QmjD5DSB3FZw8c3+lpHvmdovGiZTerQcjumStnLbKeBbX5a4EbXqATJvUPZM73Om2z+otq/3faWFREclcNzdKc61AgLBFjQAAAABJRU5ErkJggg==" />.


Trusted reader
==============

I'm reading my friend's writing, when I see:
<img style="max-height: 1.5ex" src="data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAJgAAAARCAYAAAAhfWUxAAAABmJLR0QA/wD/AP+gvaeTAAAACXBIWXMAAAsTAAALEwEAmpwYAAAAB3RJTUUH5QEXBhwiTWkGDAAAAB1pVFh0Q29tbWVudAAAAAAAQ3JlYXRlZCB3aXRoIEdJTVBkLmUHAAABrElEQVRo3u1awbLDIAgEx///Zd/pdaijCLhG25pTawyuK+BiwqWUQvdqXsxMREQ9ipiZTqZvB76asywb60sj1trXCgg1pseeBTNigSQmzR6SVyS+nn+0nimlvPVPsw5hBWF9xtrWapfR8z/pnr3RwmnzYebXfflb6/c0r2h80bXN0WiRfWedy2prdsyZ5yyO0OOvjuqneEXh07LayGdSBHxtVMsW3pRc/0eNGQmkHhZ5T2bL1vOWsVbyisA3w2+OaIUVQE4SvR7NsWsun4CPmd8dbEcFYhXlJ1aXv4rPYz/V6RKhc9Ai3xu5UrzKtvq+V+T2tMgpDvc0PksyyL29f4UYHqVuWflEM1mP5FrP1M7m1WWtCnZHxm8dE+zENyXyV0fAJ535tkT0SVvnKnxeG/lbBPxuLblzGzwZR/LoIC39Rsr/nh3UmNGI9bxNQGQGFK+r8M3MK/SqCAna83pk5ZmXNftpQTHqazkKQmtfJL7IeVzSDuEQ7d6F95zhjAJAs9WqNGecdXbrQvC6El/UFt+vKeL67X5NMR43XTfCVk2XL36mirwV2+WMiOgPrf2gSoHBkWMAAAAASUVORK5CYII=" />

I click it. (**TODO: why?**) I'm directed, of course, to `biatob.com/bet/12345`:

<div style="margin: 1em; border: 1px solid black; padding: 2em">
  <h2>Will the cat barf on the rug in January 1962?</h2>
  Spencer assigns this a 50-60% chance. <br />
  Buy up to 10 "IOU $1 if yes" tickets, at $0.50 apiece? <input type="number" value="5" step="1" /><button>Buy</button><br />
  Buy up to 17 "IOU $1 if no" tickets, at $0.60 apiece? <input type="number" value="5" step="1" /><button>Buy</button><br />
  Offer open until EOD 1961-12-31. Spencer intends to settle debts by 1962-01-31.<br />
  Guidelines: If you see the cat barf on the rug, and then place a bet, that's cheating. If the cat dies before January, that invalidates the market.<br/>
  Participants:
    <table>
      <tr><th>Who</th><th>+IOUs</th><th>-IOUs</th></tr>
      <tr><td>Alice</td><td>6</td><td></td></tr>
      <tr><td>Bob</td><td>4</td><td></td></tr>
      <tr><td>Charlie</td><td></td><td>3</td></tr>
    </table>
</div>

I think the cat is pretty likely to barf, so I click the first "Buy". The page reloads.

<div style="margin: 1em; border: 1px solid black; padding: 2em">
  <h2>Will the cat barf on the rug in January 1962?</h2>
  Spencer assigns this a 50-60% chance. <br />
  Buy up to 10 "IOU $1 if yes" tickets, at $0.50 apiece? <input type="number" value="5" step="1" /><button>Buy</button><br />
  Buy up to 17 "IOU $1 if no" tickets, at $0.60 apiece? <input type="number" value="5" step="1" /><button>Buy</button><br />
  Offer open until EOD 1961-12-31. Spencer intends to settle debts by 1962-01-31.<br />
  Guidelines: If you see the cat barf on the rug, and then place a bet, that's cheating. If the cat dies before January, that invalidates the market.<br/>
  Participants:
    <table>
      <tr><th>Who</th><th>+IOUs</th><th>-IOUs</th></tr>
      <tr style="color:red"><td>Me</td><td>5</td><td></td></tr>
      <tr><td>Alice</td><td>6</td><td></td></tr>
      <tr><td>Bob</td><td>4</td><td></td></tr>
      <tr><td>Charlie</td><td></td><td>3</td></tr>
    </table>
</div>

I check back in January. The page now reads:

<div style="margin: 1em; border: 1px solid black; padding: 2em">
  <h2>Will the cat barf on the rug in January 1962?</h2>
  Spencer assigns this a 50-60% chance. <br />
  Trades closed EOD 1961-12-31. Spencer intends to settle debts by 1962-01-31.<br />
  Guidelines: If you see the cat barf on the rug, and then place a bet, that's cheating. If the cat dies before January, that invalidates the market.<br/>
  Participants:
    <table>
      <tr><th>Who</th><th>+IOUs</th><th>-IOUs</th></tr>
      <tr style="color:red"><td>Me</td><td>5</td><td></td></tr>
      <tr><td>(unclaimed)</td><td>5</td><td>17</td></tr>
      <tr><td>Alice</td><td>6</td><td></td></tr>
      <tr><td>Bob</td><td>4</td><td></td></tr>
      <tr><td>Charlie</td><td></td><td>3</td></tr>
    </table>
</div>

I check back in February. The page now reads:

<div style="margin: 1em; border: 1px solid black; padding: 2em">
  <h2>Will the cat barf on the rug in January 1962?</h2>
  Spencer assigns this a 50-60% chance. <br />
  Trades closed EOD 1961-12-31. Spencer intended to settle debts by 1962-01-31.<br />
  Guidelines: If you see the cat barf on the rug, and then place a bet, that's cheating. If the cat dies before January, that invalidates the market.<br/>
  Participants:
    <table>
      <tr><th>Who</th><th>+IOUs</th><th>-IOUs</th></tr>
      <tr style="color:red"><td>Me</td><td>5</td><td></td></tr>
      <tr><td>(unclaimed)</td><td>5</td><td>17</td></tr>
      <tr><td>Alice</td><td>6</td><td></td></tr>
      <tr><td>Bob</td><td>4</td><td></td></tr>
      <tr><td>Charlie</td><td></td><td>3</td></tr>
    </table>
</div>

I check back a few days later. The page now reads:

<div style="margin: 1em; border: 1px solid black; padding: 2em">
  <h2>Will the cat barf on the rug in January 1962?</h2>
  <strong>Spencer claims that this market resolved False, and to have settled all his debts.</strong><br />
  Spencer assigned this a 50-60% chance. <br />
  <hr/>
  Trades closed EOD 1961-12-31. intended to settle debts by 1962-01-31.<br />
  Participants:
    <table>
      <tr><th>Who</th><th>+IOUs</th><th>-IOUs</th></tr>
      <tr style="color:red"><td>Me</td><td>5</td><td></td></tr>
      <tr><td>(unclaimed)</td><td>5</td><td>17</td></tr>
      <tr><td>Alice</td><td>6</td><td></td></tr>
      <tr><td>Bob</td><td>4</td><td></td></tr>
      <tr><td>Charlie</td><td></td><td>3</td></tr>
    </table>
</div>
