<script>
  export let page = 'privacy';
  const isPrivacy = page === 'privacy';
</script>

<svelte:head><title>{isPrivacy ? 'Privacy Policy' : 'Support'} — Hoops IQ</title></svelte:head>
<a class="skip-link" href="#main-content">Skip to content</a>
<header class="site-header shell"><a class="brand" href="/" aria-label="Hoops IQ home"><span class="brand-mark" aria-hidden="true">H</span><span>HOOPS IQ</span></a><nav aria-label="Primary navigation"><a href="/#games">Games</a><a href="/#how-it-works">How it works</a><a href="/support.html">Support</a></nav></header>
<main id="main-content" class="info-main shell">
  {#if isPrivacy}
    <p class="kicker"><span></span> LAST UPDATED AUGUST 1, 2026</p><h1>Privacy, in<br /><em>plain language.</em></h1><p class="info-lede">Hoops IQ is operated by Jack Ziegler. Questions about this policy can be sent to <a href="mailto:wumby5@gmail.com">wumby5@gmail.com</a>.</p>
    <article class="info-content">
      <section><h2>The short version</h2><p>Hoops IQ does not include advertising, analytics, or third-party tracking. The app does not collect personal data for Jack Ziegler. It stores game progress and ranked state on your device. Optional Game Center features are provided by Apple.</p></section>
      <section><h2>Information stored on your device</h2><p>Hoops IQ uses on-device storage to keep your game settings, local progress, game history, ranked ratings, season markers, and pending leaderboard submissions. This information stays on the device unless you choose to use a Game Center feature.</p></section>
      <section><h2>Game Center</h2><p>If you sign in to Game Center, Apple provides the Game Center service. Hoops IQ uses it to authenticate you, create friend and ranked matches, show Game Center display names in matches or leaderboards, and submit or read ranked leaderboard scores. Apple’s handling of Game Center information is governed by Apple’s privacy policy and your Game Center settings.</p><p>Game Center is optional for practice play. Ranked play, leaderboards, and friend matches require Game Center sign-in.</p></section>
      <section><h2>Sharing and selling</h2><p>Jack Ziegler does not sell, rent, or share personal information for advertising. Hoops IQ does not use advertising SDKs, analytics SDKs, or cross-app tracking.</p></section>
      <section><h2>Children</h2><p>Hoops IQ does not knowingly collect personal information from children. If you believe a child has provided personal information directly to the operator, contact <a href="mailto:wumby5@gmail.com">wumby5@gmail.com</a>.</p></section>
      <section><h2>Changes and contact</h2><p>This policy may be updated if the app’s data practices change. The updated date above will change when that happens. For privacy questions or requests, email <a href="mailto:wumby5@gmail.com">wumby5@gmail.com</a>.</p></section>
    </article>
  {:else}
    <p class="kicker"><span></span> WE’RE HERE TO HELP</p><h1>Support for<br /><em>people who know ball.</em></h1><p class="info-lede">For Hoops IQ help, email <a href="mailto:wumby5@gmail.com">wumby5@gmail.com</a>. Include your device, iOS version, and a short description of what happened.</p>
    <article class="info-content support-content">
      <section><h2>Game Center sign-in</h2><p>Game Center powers ranked play, leaderboards, and friend matches. On iPhone, open Settings, tap Game Center, and sign in with your Apple Account. Return to Hoops IQ and try again. Practice play is available without Game Center.</p></section>
      <section><h2>Ranked fallback and score sync</h2><p>If a ranked opponent is not found, Hoops IQ may offer an AI fallback so you can keep playing. Your local ranked result is saved first. If Game Center cannot accept a leaderboard update immediately, the app keeps it pending and lets you retry once Game Center is available.</p></section>
      <section><h2>Friend matches</h2><p>Friend matches use Game Center. Confirm that both players are signed in, then create a private challenge from the game’s Friend Match option. Friend matches do not affect ranked ratings. If an invite fails, close the matchmaker, check Game Center sign-in, and try again.</p></section>
      <section><h2>Report a problem</h2><p>Email <a href="mailto:wumby5@gmail.com">wumby5@gmail.com</a> with the game mode, what you expected, what happened, and any relevant Game Center message. Do not send passwords or other sensitive information.</p></section>
      <section><h2>Rights-holder contact</h2><p>Hoops IQ is an independent product and is not affiliated with or endorsed by any basketball league, players association, team, or rights holder. Rights holders with a question or request can contact <a href="mailto:wumby5@gmail.com">wumby5@gmail.com</a>.</p></section>
    </article>
  {/if}
</main>
<footer class="site-footer shell"><a class="brand" href="/"><span class="brand-mark" aria-hidden="true">H</span><span>HOOPS IQ</span></a><p>© {new Date().getFullYear()} JACK ZIEGLER</p><nav aria-label="Footer navigation"><a href="/privacy.html">Privacy</a><a href="/support.html">Support</a></nav></footer>
