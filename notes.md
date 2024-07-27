## CCIP Sucker Language

I left a number of notes throughout. Please `grep -ri "TODO" src`!

### Deployer

- It looks like the "layer-specific configurator" is only respected by the `CCIPSuckerDeployer`. Can we remove it from the base/arb/optimism suckers?
- Why is `_admin` (in constructor args for deployer, formerly `_configurator`) prefixed with an underscore?
- Do I understand correctly that each deployer only deploys CCIP suckers for a single lane? Why?
- Should it be possible to call `JBCCIPSuckerDeployer.setChainSpecificConstants(…)` multiple times?

### Sucker

- For my own edification – why does `_isRemotePeer` need to accept `sender` as an arg? Could it not just check `msg.sender` directly?
- Where does `i_ccipRouter` get defined (when used in the constructor, on line 66).