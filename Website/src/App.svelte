<script>
  const storeUrl = import.meta.env.VITE_APP_STORE_URL?.trim();
  const storeReady = Boolean(storeUrl);
  const games = [
    { title: 'Five Alive', tag: 'BUILD THE BEST FIVE', copy: 'Bid on legendary team-years, draft the right player, and outbuild your rival.', screen: 'five' },
    { title: 'Box Wars', tag: '90-SECOND BOX FIGHT', copy: 'Fill a four-square grid with players who match both clues before the buzzer.', screen: 'box' }
  ];

  function StoreButton({ compact = false } = {}) {
    return storeReady
      ? { href: storeUrl, label: compact ? 'Get the app' : 'Download on the App Store', disabled: false }
      : { href: undefined, label: 'Coming soon to the App Store', disabled: true };
  }

  const download = StoreButton();
</script>

<svelte:head>
  <title>Hoops IQ — Basketball knowledge, tested.</title>
  <meta name="description" content="Hoops IQ is an independent basketball knowledge game for iPhone, with Five Alive and Box Wars." />
</svelte:head>

<a class="skip-link" href="#main-content">Skip to content</a>
<header class="site-header shell">
  <a class="brand" href="/" aria-label="Hoops IQ home"><span class="brand-mark" aria-hidden="true">H</span><span>HOOPS IQ</span></a>
  <nav aria-label="Primary navigation"><a href="#games">Games</a><a href="#how-it-works">How it works</a><a href="/support.html">Support</a></nav>
  {#if storeReady}
    <a class="header-cta" href={download.href} target="_blank" rel="noopener noreferrer">Get the app <span aria-hidden="true">↗</span></a>
  {:else}
    <span class="header-cta muted" aria-label="Coming soon to the App Store">Coming soon</span>
  {/if}
</header>

<main id="main-content">
  <section class="hero shell">
    <div class="hero-copy">
      <p class="kicker"><span></span> BASKETBALL KNOWLEDGE, TESTED</p>
      <h1>Know the game.<br /><em>Own the room.</em></h1>
      <p class="lede">Hoops IQ turns basketball history into fast, thoughtful games for the people who remember the seasons, the lineups, and the deep cuts.</p>
      {#if storeReady}
        <a class="button primary" href={download.href} target="_blank" rel="noopener noreferrer">{download.label}<span aria-hidden="true">→</span></a>
      {:else}
        <span class="button primary disabled" aria-disabled="true">{download.label}<span aria-hidden="true">•</span></span>
      {/if}
      <p class="availability">FOR iPHONE · INDEPENDENT BASKETBALL TRIVIA</p>
    </div>
    <div class="hero-phone-wrap" aria-label="Illustrated Hoops IQ home screen">
      <div class="glow glow-one"></div><div class="glow glow-two"></div>
      <div class="phone home-phone">
        <div class="phone-island"></div>
        <div class="screen home-screen"><div class="screen-top"><span class="mini-brand">H</span><span>HOOPS IQ</span><i>•••</i></div><p class="screen-label">PICK YOUR GAME</p><div class="home-game-card pink"><b>FIVE<br />ALIVE</b><span>BUILD THE BEST FIVE →</span><i class="court" aria-hidden="true"></i></div><div class="home-game-card violet"><b>BOX<br />WARS</b><span>FILL THE GRID →</span><i class="tiny-grid" aria-hidden="true"></i></div><p class="screen-footer">MORE GAMES · COMING SOON</p></div>
      </div>
      <div class="floating-score"><small>YOUR STREAK</small><b>07</b><span>games</span></div>
    </div>
  </section>

  <div class="ticker" aria-label="Hoops IQ highlights"><div>HISTORY HAS RECEIPTS <b>✦</b> RARE KNOWLEDGE WINS <b>✦</b> BUILD. BID. WIN. <b>✦</b> HISTORY HAS RECEIPTS <b>✦</b> RARE KNOWLEDGE WINS <b>✦</b> BUILD. BID. WIN. <b>✦</b></div></div>

  <section class="games shell" id="games">
    <div class="section-intro"><p class="kicker"><span></span> PICK YOUR TEST</p><h2>Two games.<br /><em>Zero easy answers.</em></h2><p>Every round rewards the details worth remembering.</p></div>
    <div class="game-list">
      {#each games as game, i}
        <article class="game-card">
          <div><p class="number">0{i + 1}</p><p class="game-tag">{game.tag}</p><h3>{game.title}</h3><p class="game-copy">{game.copy}</p></div>
          <div class="mini-phone" class:box-phone={game.screen === 'box'} aria-label={`Illustrated ${game.title} screen`}>
            <div class="mini-phone-head"></div>
            {#if game.screen === 'five'}
              <p>YOUR FIVE</p><div class="lineup"><i></i><i></i><i></i><i></i><i></i></div><b>BUILD. BID. WIN.</b>
            {:else}
              <p>00:54 <span>BOX WARS</span></p><div class="answer-grid"><i>12+</i><i>ALL-STAR</i><i>WINNER</i><i>GUARD</i></div><b>4 / 4 FOUND</b>
            {/if}
          </div>
        </article>
      {/each}
    </div>
  </section>

  <section class="play-section" id="how-it-works"><div class="shell play-layout"><div><p class="kicker"><span></span> PLAY YOUR WAY</p><h2>Practice. Compete.<br /><em>Run it back.</em></h2><p class="lede">Sharpen your memory against an AI rival, invite a friend through Game Center, or queue for the monthly ranked ladder.</p><div class="modes"><div><b>01</b><span>Practice</span><small>Take your time and learn the archive.</small></div><div><b>02</b><span>Friend match</span><small>Send a private Game Center challenge.</small></div><div><b>03</b><span>Ranked ladder</span><small>Climb with separate Five Alive and Box Wars ratings.</small></div></div></div><div class="rank-phone" aria-label="Illustrated ranked ladder screen"><div class="rank-phone-head"></div><p class="screen-label">MONTHLY LADDER</p><img class="rank-emblem" src="/images/FiveAliveRankGold.png" alt="Gold Five Alive rank emblem" /><h3>Gold division</h3><div class="rating"><span>YOUR RATING</span><b>1280</b><i>+24</i></div><button type="button">QUEUE FOR RANKED</button><p class="rank-note">Game Center sign-in required</p></div></div></section>

  <section class="results shell"><div class="result-copy"><p class="kicker"><span></span> NO GUESSWORK</p><h2>See how your<br /><em>knowledge stacks up.</em></h2><p class="lede">Results make every answer part of the conversation: find the rarity, see the score, then come back better next time.</p></div><div class="results-card" aria-label="Illustrated results screen"><div><span>ROUND COMPLETE</span><b>82</b><small>POINTS</small></div><ul><li><i></i><span>Archive pull</span><b>+32</b></li><li><i></i><span>Rare answer</span><b>+28</b></li><li><i></i><span>Quick finish</span><b>+22</b></li></ul></div></section>

  <section class="final-cta shell"><p class="kicker"><span></span> YOUR TURN</p><h2>How well do you<br />really know <em>ball?</em></h2>{#if storeReady}<a class="button primary" href={download.href} target="_blank" rel="noopener noreferrer">Get Hoops IQ <span aria-hidden="true">→</span></a>{:else}<span class="button primary disabled" aria-disabled="true">Coming soon to the App Store <span aria-hidden="true">•</span></span>{/if}</section>
</main>

<footer class="site-footer shell"><a class="brand" href="/"><span class="brand-mark" aria-hidden="true">H</span><span>HOOPS IQ</span></a><p>© {new Date().getFullYear()} JACK ZIEGLER</p><nav aria-label="Footer navigation"><a href="/privacy.html">Privacy</a><a href="/support.html">Support</a></nav></footer>
