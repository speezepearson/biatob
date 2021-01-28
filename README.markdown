This is a harebrained idea for a project to glorify betting. It provides a mechanism for writers to include little tags in their writing that indicate a willingness to bet on their claims.

This project does not touch real money: financial stuff is really hard; appropriate security is really hard; and it would probably be illegal. So, this project assumes an honor system. People will use it to make bets _with their friends,_ or people they trust, at least.

See [./mockup/user-stories.markdown](./mockup/user-stories.markdown) for descriptions of who uses this and how.

Development
-----------

This project uses the `doit` build system: https://pydoit.org/tutorial_1.html

`doit list` lists all the targets.

`doit proto` builds the `proto` target.

Extrapolate.


TODO
--------------
- sketch the signup process, and how trust is establihed between accounts
- write copy explaining how to operationalize a bet well
- consider a semi-formalized system for naming an arbiter
- consider allowing "soft resolutions" so a market can resolve "80% yes"
- figure out an accounting system that track how many "points" people owe each other
- figure out how users can undo accidental bets
- figure out how to round things properly for display
- monetize via freemium or subscription?
- advertise to Caplan/Hanson/LessWrong/EAG/CFAR?
- add "Sign in with [identity provider]"
