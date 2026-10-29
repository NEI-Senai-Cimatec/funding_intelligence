// ============================================================================
// Funding Intelligence - Autenticação Supabase, Sessão e Interface de Acesso
// SENAI CIMATEC – Núcleo de Economia Industrial (NEI)
// ============================================================================

(function() {
  'use strict';

  // Inicialização do SDK Oficial do Supabase (Padrão comprovado nei-js)
  var SUPABASE_URL = (window.SUPABASE_CONFIG && window.SUPABASE_CONFIG.url) || "https://jsystdrhtcoopjkrcwql.supabase.co";
  var SUPABASE_ANON_KEY = (window.SUPABASE_CONFIG && window.SUPABASE_CONFIG.anonKey) || "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImpzeXN0ZHJodGNvb3Bqa3Jjd3FsIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTA4Njk5MzksImV4cCI6MjEwNjQ0NTkzOX0.2zCgYRema1h-KAz7ibQmoJfrmvVfoJTjMaKBeB18j98";
  var supabaseClient = null;
  try {
    if (window.supabase && typeof window.supabase.createClient === 'function') {
      supabaseClient = window.supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY);
      console.log('[AUTH] Supabase SDK Client v2 inicializado com sucesso.');
    }
  } catch(e) {
    console.warn('[AUTH] Aviso ao inicializar Supabase Client:', e);
  }

  // 1. Funções Globais de Submissão de Formulário (sempre disponíveis)
  window.submitLoginForm = function() {
    var emailInput = document.getElementById('login_email');
    var pwdInput = document.getElementById('login_password');
    var errBox = $('#auth_login_error_box');
    var errText = $('#auth_login_error_text');
    var successBox = $('#auth_login_success_box');
    var btn = $('#btn_login_submit');

    var email = emailInput ? emailInput.value.trim() : '';
    var pwd = pwdInput ? pwdInput.value : '';

    if (!email || !pwd) {
      errText.text('Por favor, informe seu e-mail institucional e senha.');
      errBox.stop(true, true).slideDown(150);
      return;
    }

    errBox.hide();
    if (successBox.length) successBox.hide();

    // Limpa quaisquer tokens residuais de recuperação anteriores para não interferir no login
    try {
      sessionStorage.removeItem('quiin_pending_recovery_token');
      sessionStorage.removeItem('quiin_em_redefinicao_senha');
      sessionStorage.removeItem('quiin_recovery_active');
      localStorage.removeItem('quiin_pending_recovery_token');
      localStorage.removeItem('quiin_recovery_active');
    } catch(e) {}
    if (window.history && window.history.replaceState) {
      var curHash = window.location.hash || '';
      var curSearch = window.location.search || '';
      if (curHash.indexOf('type=recovery') !== -1 || curSearch.indexOf('type=recovery') !== -1) {
        window.history.replaceState(null, document.title, window.location.pathname);
      }
    }

    // Feedback visual imediato e animação no botão
    btn.prop('disabled', true).addClass('loading');
    btn.html('<i class="fa fa-spinner fa-spin" style="margin-right: 8px;"></i><span>Entrando na plataforma...</span>');

    var payload = { email: email, password: pwd, timestamp: Date.now() };

    if (window.Shiny && window.Shiny.setInputValue) {
      Shiny.setInputValue('login_email', email);
      Shiny.setInputValue('login_password', pwd);
      Shiny.setInputValue('btn_login_submit', payload, {priority: 'event'});
    } else {
      setTimeout(function() {
        if (window.Shiny && window.Shiny.setInputValue) {
          Shiny.setInputValue('login_email', email);
          Shiny.setInputValue('login_password', pwd);
          Shiny.setInputValue('btn_login_submit', payload, {priority: 'event'});
        } else {
          btn.prop('disabled', false).removeClass('loading');
          btn.html('<i class="fa fa-right-to-bracket" style="margin-right: 8px;"></i><span>Entrar na Plataforma</span>');
          errText.text('Conectando ao servidor... Tente novamente em alguns segundos.');
          errBox.slideDown(150);
        }
      }, 500);
    }
  };

  window.submitSignupForm = function() {
    var emailInput = document.getElementById('signup_email');
    var pwdInput = document.getElementById('signup_password');
    var pwdConfInput = document.getElementById('signup_password_confirm');
    var errBox = $('#auth_signup_error_box');
    var errText = $('#auth_signup_error_text');
    var btn = $('#btn_signup_submit');

    var email = emailInput ? emailInput.value.trim() : '';
    var pwd = pwdInput ? pwdInput.value : '';
    var pwdConf = pwdConfInput ? pwdConfInput.value : '';

    if (!email || !pwd) {
      errText.text('Por favor, informe seu e-mail institucional e defina uma senha.');
      errBox.stop(true, true).slideDown(150);
      return;
    }

    if (pwd !== pwdConf) {
      errText.text('As senhas digitadas não coincidem.');
      errBox.stop(true, true).slideDown(150);
      return;
    }

    if (pwd.length < 6) {
      errText.text('A senha deve conter no mínimo 6 caracteres.');
      errBox.stop(true, true).slideDown(150);
      return;
    }

    errBox.hide();

    // Feedback visual imediato e animação no botão
    btn.prop('disabled', true).addClass('loading');
    btn.html('<i class="fa fa-spinner fa-spin" style="margin-right: 8px;"></i><span>Cadastrando na plataforma...</span>');

    var payload = { email: email, password: pwd, password_confirm: pwdConf, timestamp: Date.now() };

    if (window.Shiny && window.Shiny.setInputValue) {
      Shiny.setInputValue('signup_email', email);
      Shiny.setInputValue('signup_password', pwd);
      Shiny.setInputValue('signup_password_confirm', pwdConf);
      Shiny.setInputValue('btn_signup_submit', payload, {priority: 'event'});
    } else {
      setTimeout(function() {
        if (window.Shiny && window.Shiny.setInputValue) {
          Shiny.setInputValue('signup_email', email);
          Shiny.setInputValue('signup_password', pwd);
          Shiny.setInputValue('signup_password_confirm', pwdConf);
          Shiny.setInputValue('btn_signup_submit', payload, {priority: 'event'});
        } else {
          btn.prop('disabled', false).removeClass('loading');
          btn.html('<i class="fa fa-user-check" style="margin-right: 8px;"></i><span>Cadastrar e Criar Conta</span>');
          errText.text('Conectando ao servidor... Tente novamente em alguns segundos.');
          errBox.slideDown(150);
        }
      }, 500);
    }
  };

  // Submissão do Formulário de Recuperação de Senha (Esqueci a Senha)
  window.submitRecoveryForm = function() {
    var emailInput = document.getElementById('recovery_email');
    var errBox = $('#auth_recovery_error_box');
    var errText = $('#auth_recovery_error_text');
    var successBox = $('#auth_recovery_success_box');
    var successText = $('#auth_recovery_success_text');
    var btn = $('#btn_recovery_submit');

    var email = emailInput ? emailInput.value.trim() : '';

    errBox.hide();
    successBox.hide();

    if (!email) {
      errText.text('Por favor, informe seu e-mail institucional para recuperar a senha.');
      errBox.stop(true, true).slideDown(150);
      return;
    }

    var emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
    if (!emailRegex.test(email)) {
      errText.text('Por favor, informe um endereço de e-mail válido.');
      errBox.stop(true, true).slideDown(150);
      return;
    }

    btn.prop('disabled', true).addClass('loading');
    btn.html('<i class="fa fa-spinner fa-spin" style="margin-right: 8px;"></i><span>Enviando link para seu e-mail...</span>');
    var redirectUri = 'https://neicimatec-radar-da-inovacao.share.connect.posit.cloud/';
    try {
      if (window.location.origin.indexOf('localhost') !== -1 || window.location.origin.indexOf('127.0.0.1') !== -1) {
        redirectUri = window.location.origin + window.location.pathname;
      } else if (window.location.origin.indexOf('share.connect.posit.cloud') !== -1) {
        redirectUri = window.location.origin + window.location.pathname;
      }
    } catch(e) {}
    var payload = { email: email, redirect_to: redirectUri, timestamp: Date.now() };

    if (window.Shiny && window.Shiny.setInputValue) {
      Shiny.setInputValue('recovery_email', email);
      Shiny.setInputValue('btn_recovery_submit', payload, {priority: 'event'});
    } else {
      setTimeout(function() {
        if (window.Shiny && window.Shiny.setInputValue) {
          Shiny.setInputValue('recovery_email', email);
          Shiny.setInputValue('btn_recovery_submit', payload, {priority: 'event'});
        } else {
          btn.prop('disabled', false).removeClass('loading');
          btn.html('<i class="fa fa-paper-plane" style="margin-right: 8px;"></i><span>Enviar Link de Recuperação</span>');
          errText.text('Não foi possível conectar ao servidor. Tente novamente em alguns segundos.');
          errBox.slideDown(150);
        }
      }, 500);
    }
  };

  // Submissão do Formulário de Redefinição de Nova Senha (via link do e-mail)
  window.submitResetPasswordForm = function() {
    var pwdInput = document.getElementById('reset_password_new');
    var pwdConfInput = document.getElementById('reset_password_confirm');
    var errBox = $('#auth_reset_error_box');
    var errText = $('#auth_reset_error_text');
    var btn = $('#btn_reset_password_submit');

    var pwd = pwdInput ? pwdInput.value : '';
    var pwdConf = pwdConfInput ? pwdConfInput.value : '';

    errBox.hide();

    if (!pwd || !pwdConf) {
      errText.text('Preencha todos os campos.');
      errBox.stop(true, true).slideDown(150);
      return;
    }

    if (pwd.length < 8) {
      errText.text('A senha deve ter pelo menos 8 caracteres.');
      errBox.stop(true, true).slideDown(150);
      return;
    }

    if (pwd !== pwdConf) {
      errText.text('As senhas não coincidem.');
      errBox.stop(true, true).slideDown(150);
      return;
    }

    btn.prop('disabled', true).addClass('loading');
    btn.html('<i class="fa fa-spinner fa-spin" style="margin-right: 8px;"></i><span>Salvando nova senha...</span>');

    var token = window.currentRecoveryToken || '';
    try {
      if (!token) token = sessionStorage.getItem('quiin_pending_recovery_token') || localStorage.getItem('quiin_pending_recovery_token') || '';
    } catch(e) {}
    var payload = { password: pwd, access_token: token, timestamp: Date.now() };

    if (window.Shiny && window.Shiny.setInputValue) {
      Shiny.setInputValue('btn_reset_password_submit', payload, {priority: 'event'});
    } else {
      setTimeout(function() {
        if (window.Shiny && window.Shiny.setInputValue) {
          Shiny.setInputValue('btn_reset_password_submit', payload, {priority: 'event'});
        } else {
          btn.prop('disabled', false).removeClass('loading');
          btn.html('<i class="fa fa-check" style="margin-right: 8px;"></i><span>Salvar Nova Senha</span>');
          errText.text('Não foi possível conectar ao servidor. Tente novamente em alguns segundos.');
          errBox.slideDown(150);
        }
      }, 500);
    }
  };

  // Estado global de recuperação de senha para evitar que restauração de sessão sobrescreva o fluxo
  var isRecoveryModeActive = false;
  var isRecoveryErrorActive = false;
  var recoveryErrorMessage = '';
  var modalTriggerAcknowledged = false;
  var recoveryPollTimer = null;
  window.allowRecoveryModalClose = false;

  // Cancela / encerra completamente o fluxo de recuperação de senha e destrava a interface
  window.cancelRecoveryModal = function(skipModalHide) {
    var isAuth = $('body').hasClass('authenticated');
    // Se NÃO estiver logado, não pode cancelar a redefinição de nova senha obrigatória
    if (!isAuth) {
      console.warn('[AUTH] Cancelamento bloqueado: usuário não autenticado em redefinição obrigatória.');
      return;
    }
    console.log('[AUTH] Fechando modal de alteração de senha de usuário autenticado...');
    if (recoveryPollTimer) {
      clearInterval(recoveryPollTimer);
      recoveryPollTimer = null;
    }
    if (!skipModalHide) {
      $('#shiny-modal').modal('hide');
    }
    if (window.Shiny && window.Shiny.setInputValue) {
      window.Shiny.setInputValue('reset_modal_closed', Date.now(), {priority: 'event'});
    }
  };

  // Submissão direta e segura do modal dedicado de nova senha
  window.submitModalPasswordReset = function() {
    var p1 = $.trim($('#modal_reset_password_new').val() || '');
    var p2 = $.trim($('#modal_reset_password_confirm').val() || '');
    var token = window.currentRecoveryToken || '';
    try {
      if (!token) token = sessionStorage.getItem('quiin_pending_recovery_token') || localStorage.getItem('quiin_pending_recovery_token') || '';
    } catch(e) {}

    var btn = $('#btn_modal_submit_new_password');
    if (!p1 || !p2) {
      // Deixa o servidor processar a validação
    } else {
      btn.prop('disabled', true);
      btn.html('<i class="fa fa-spinner fa-spin" style="margin-right: 6px;"></i><span>Salvando...</span>');
    }

    if (window.Shiny && window.Shiny.setInputValue) {
      window.Shiny.setInputValue('modal_reset_password_new', p1);
      window.Shiny.setInputValue('modal_reset_password_confirm', p2);
      window.Shiny.setInputValue('btn_modal_submit_new_password_custom', {
        password: p1,
        confirm: p2,
        token: token,
        timestamp: Date.now()
      }, {priority: 'event'});
    } else {
      $('#btn_modal_submit_new_password').click();
    }
  };

  // Verifica se o usuário está em fluxo de recuperação (ativo, em memória, sessionStorage ou URL)
  window.isUserInRecovery = function() {
    if (document.body && document.body.classList.contains('authenticated')) return false;

    var params = collectAllUrlParams();
    var hasRecoveryUrl = (params.type === 'recovery') || 
                         (params.recovery === 'true') || 
                         (window.location.hash.indexOf('type=recovery') !== -1) ||
                         (window.location.search.indexOf('type=recovery') !== -1) ||
                         (window.location.hash.indexOf('token_hash=') !== -1) ||
                         (window.location.search.indexOf('token_hash=') !== -1);

    var hasSavedAuth = false;
    try {
      if (localStorage.getItem('quiin_auth_session')) {
        hasSavedAuth = true;
      } else {
        for (var k in localStorage) {
          if (k.indexOf('-auth-token') !== -1 && localStorage.getItem(k)) {
            hasSavedAuth = true;
            break;
          }
        }
      }
    } catch(e) {}

    // Se o usuário já possui sessão salva e a URL NÃO é explicitamente de recuperação, NUNCA está em recuperação
    if (hasSavedAuth && !hasRecoveryUrl) {
      try {
        sessionStorage.removeItem('quiin_em_redefinicao_senha');
        sessionStorage.removeItem('nei_em_redefinicao_senha');
      } catch(e) {}
      return false;
    }

    var storedToken = null;
    var storedFlag = null;
    try {
      storedToken = sessionStorage.getItem('quiin_pending_recovery_token');
      storedFlag = sessionStorage.getItem('quiin_em_redefinicao_senha') || sessionStorage.getItem('nei_em_redefinicao_senha');
    } catch(e) {}

    return isRecoveryModeActive || hasRecoveryUrl || (!!storedToken && storedToken.length > 5) || (storedFlag === '1');
  };

  // Destaque visual (.shake) quando o usuário tenta fechar ou sair do modo de redefinição (padrão nei-js)
  window.destacarCaixaAuth = function() {
    var card = document.querySelector('.auth-card');
    if (card) {
      card.classList.remove('shake');
      void card.offsetWidth; // Força reflow para reiniciar a animação
      card.classList.add('shake');
    }
    var pwd = document.getElementById('reset_password_new');
    if (pwd) {
      try { pwd.focus(); } catch(e) {}
    }
  };

  // Cancela a redefinição de senha e retorna com segurança para a tela de login (padrão nei-js)
  window.cancelarRedefinicaoSenha = function() {
    console.log('[AUTH] Usuário cancelou a redefinição de senha. Retornando ao login...');
    isRecoveryModeActive = false;
    window.currentRecoveryToken = null;
    try {
      sessionStorage.removeItem('quiin_pending_recovery_token');
      sessionStorage.removeItem('quiin_em_redefinicao_senha');
      sessionStorage.removeItem('nei_em_redefinicao_senha');
      sessionStorage.removeItem('quiin_recovery_active');
      localStorage.removeItem('quiin_pending_recovery_token');
      localStorage.removeItem('quiin_recovery_active');
    } catch(e) {}
    if (supabaseClient && supabaseClient.auth) {
      try { supabaseClient.auth.signOut(); } catch(e) {}
    }
    if (window.history && window.history.replaceState) {
      window.history.replaceState(null, document.title, window.location.pathname);
    }
    try {
      var s1 = document.getElementById('quiin_recovery_instant_css');
      if (s1) s1.remove();
      var s2 = document.getElementById('quiin_restore_instant_css');
      if (s2) s2.remove();
    } catch(e) {}
    if (window.$) {
      $('#quiin_recovery_instant_css, #quiin_restore_instant_css').remove();
    }
    window.exibirModoAuth('login');
  };

  // Desbloqueio forçado manual para o usuário voltar ao login se a rede/servidor demorar
  window.forceUnlockLogin = function() {
    window.cancelarRedefinicaoSenha();
  };

  // 2. Função Mestre de Exibição com Exclusão Mútua Rígida (padrão nei-js)
  window.exibirModoAuth = function(modo) {
    var isAuth = document.body && document.body.classList.contains('authenticated');
    if (isAuth) return;

    var elRecoveryLoading = document.getElementById('auth_recovery_loading_state');
    var elRestoring = document.getElementById('auth_restoring_state');
    var elLogin = document.getElementById('auth_form_login');
    var elSignup = document.getElementById('auth_form_signup');
    var elForgot = document.getElementById('auth_form_forgot');
    var elReset = document.getElementById('auth_form_reset_password');
    var elTabs = document.querySelector('.auth-tabs-nav');

    // Remove estilos temporários de bloqueio inicial
    try {
      var s1 = document.getElementById('quiin_recovery_instant_css');
      if (s1) s1.remove();
      var s2 = document.getElementById('quiin_restore_instant_css');
      if (s2) s2.remove();
    } catch(e) {}
    if (window.$) {
      $('#quiin_recovery_instant_css, #quiin_restore_instant_css').remove();
      $('#auth_overlay_root').show();
      $('body').removeClass('authenticated');
    }

    // Se os elementos ainda não foram injetados no DOM, reagenda
    if (!elLogin || !elReset) {
      if (window.$) {
        $(document).ready(function() { window.exibirModoAuth(modo); });
      } else {
        document.addEventListener('DOMContentLoaded', function() { window.exibirModoAuth(modo); });
      }
      setTimeout(function() { window.exibirModoAuth(modo); }, 50);
      return;
    }

    // Se o usuário está em fluxo de redefinição de senha e tenta ir para outra tela sem cancelar
    if (window.isUserInRecovery() && modo !== 'reset') {
      console.warn('[AUTH] Usuário preso no fluxo de redefinição de senha. Destacando caixa.');
      window.destacarCaixaAuth();
      return;
    }

    // 1. Oculta rigorosamente todos os formulários e estados
    if (elRecoveryLoading) elRecoveryLoading.style.setProperty('display', 'none', 'important');
    if (elRestoring) elRestoring.style.setProperty('display', 'none', 'important');
    if (elLogin) elLogin.style.setProperty('display', 'none', 'important');
    if (elSignup) elSignup.style.setProperty('display', 'none', 'important');
    if (elForgot) elForgot.style.setProperty('display', 'none', 'important');
    if (elReset) elReset.style.setProperty('display', 'none', 'important');

    // 2. Limpa caixas de erro
    if (window.$) {
      $('#auth_login_error_box, #auth_signup_error_box, #auth_recovery_error_box, #auth_recovery_success_box, #auth_reset_error_box').hide();
    }

    // 3. Reseta botões se estiverem em loading
    var btnLogin = $('#btn_login_submit');
    btnLogin.prop('disabled', false).removeClass('loading');
    btnLogin.html('<i class="fa fa-right-to-bracket" style="margin-right: 8px;"></i><span>Entrar na Plataforma</span>');

    var btnSignup = $('#btn_signup_submit');
    btnSignup.prop('disabled', false).removeClass('loading');
    btnSignup.html('<i class="fa fa-user-check" style="margin-right: 8px;"></i><span>Cadastrar e Criar Conta</span>');

    var btnRecovery = $('#btn_recovery_submit');
    btnRecovery.prop('disabled', false).removeClass('loading');
    btnRecovery.html('<i class="fa fa-paper-plane" style="margin-right: 8px;"></i><span>Enviar Link de Recuperação</span>');

    var btnReset = $('#btn_reset_password_submit');
    btnReset.prop('disabled', false).removeClass('loading');
    btnReset.html('<i class="fa fa-check" style="margin-right: 8px;"></i><span>Salvar Nova Senha</span>');

    // 4. Exibe estritamente o formulário solicitado
    if (modo === 'reset') {
      if (elTabs) elTabs.style.setProperty('display', 'none', 'important');
      if (elReset) {
        elReset.style.setProperty('display', 'block', 'important');
        var pwdInp = document.getElementById('reset_password_new');
        if (pwdInp) {
          setTimeout(function() { pwdInp.focus(); }, 80);
        }
      }
    } else if (modo === 'forgot') {
      if (elTabs) elTabs.style.setProperty('display', 'none', 'important');
      if (elForgot) {
        elForgot.style.setProperty('display', 'block', 'important');
        var loginEmail = document.getElementById('login_email');
        var recoveryEmail = document.getElementById('recovery_email');
        if (loginEmail && recoveryEmail && loginEmail.value.trim() && !recoveryEmail.value.trim()) {
          recoveryEmail.value = loginEmail.value.trim();
        }
        if (recoveryEmail) {
          setTimeout(function() { recoveryEmail.focus(); }, 80);
        }
      }
    } else if (modo === 'signup') {
      if (elTabs) elTabs.style.setProperty('display', 'flex', 'important');
      if (window.$) {
        $('.auth-tab-btn').removeClass('active');
        $('.auth-tab-btn[data-mode="signup"]').addClass('active');
      }
      if (elSignup) {
        elSignup.style.setProperty('display', 'block', 'important');
        var signEmail = document.getElementById('signup_email');
        if (signEmail) {
          setTimeout(function() { signEmail.focus(); }, 80);
        }
      }
    } else { // default: login
      if (elTabs) elTabs.style.setProperty('display', 'flex', 'important');
      if (window.$) {
        $('.auth-tab-btn').removeClass('active');
        $('.auth-tab-btn[data-mode="login"]').addClass('active');
      }
      if (elLogin) {
        elLogin.style.setProperty('display', 'block', 'important');
        var logEmail = document.getElementById('login_email');
        if (logEmail) {
          setTimeout(function() { logEmail.focus(); }, 80);
        }
      }
    }
  };

  // Funções de compatibilidade mapeadas para a função mestre
  window.switchAuthTab = function(mode) {
    window.exibirModoAuth(mode);
  };
  window.enforceResetTab = function() {
    window.exibirModoAuth('reset');
  };

  // Delegação de cliques para as abas
  $(document).on('click', '.auth-tab-btn', function(e) {
    e.preventDefault();
    var mode = $(this).attr('data-mode');
    window.switchAuthTab(mode);
  });

  $(document).ready(function() {
    // Mostrar / Ocultar Senha
    $(document).on('click', '.btn-toggle-pwd', function(e) {
      e.preventDefault();
      var targetId = $(this).data('target');
      var input = $('#' + targetId);
      var icon = $(this).find('i');
      if (input.attr('type') === 'password') {
        input.attr('type', 'text');
        icon.removeClass('fa-eye').addClass('fa-eye-slash');
      } else {
        input.attr('type', 'password');
        icon.removeClass('fa-eye-slash').addClass('fa-eye');
      }
    });

    // Submissão com tecla ENTER nos campos (usando keydown para máxima compatibilidade)
    $(document).on('keydown', '#login_email, #login_password', function(e) {
      if (e.key === 'Enter' || e.keyCode === 13 || e.which === 13) {
        e.preventDefault();
        window.submitLoginForm();
      }
    });

    $(document).on('keydown', '#signup_email, #signup_password, #signup_password_confirm', function(e) {
      if (e.key === 'Enter' || e.keyCode === 13 || e.which === 13) {
        e.preventDefault();
        window.submitSignupForm();
      }
    });

    $(document).on('keydown', '#recovery_email', function(e) {
      if (e.key === 'Enter' || e.keyCode === 13 || e.which === 13) {
        e.preventDefault();
        window.submitRecoveryForm();
      }
    });

    $(document).on('keydown', '#reset_password_new, #reset_password_confirm', function(e) {
      if (e.key === 'Enter' || e.keyCode === 13 || e.which === 13) {
        e.preventDefault();
        window.submitResetPasswordForm();
      }
    });

    // Submissão com ENTER nos campos do modal dedicado de reset de senha
    $(document).on('keydown', '#modal_reset_password_new, #modal_reset_password_confirm', function(e) {
      if (e.key === 'Enter' || e.keyCode === 13 || e.which === 13) {
        e.preventDefault();
        window.submitModalPasswordReset();
      }
    });

    // Previne saída da redefinição clicando no backdrop ou usando tecla ESC (padrão nei-js)
    $(document).on('click', '#auth_overlay_root', function(e) {
      if (e.target === this && window.isUserInRecovery && window.isUserInRecovery()) {
        window.destacarCaixaAuth();
      }
    });

    $(document).on('keydown', function(e) {
      if ((e.key === 'Escape' || e.keyCode === 27) && window.isUserInRecovery && window.isUserInRecovery()) {
        e.preventDefault();
        window.destacarCaixaAuth();
      }
    });

    // Limpa mensagem de erro dinamicamente ao digitar nos campos do modal
    $(document).on('input', '#modal_reset_password_new, #modal_reset_password_confirm', function() {
      $('#modal_reset_password_error_ui').empty();
    });

    // Impede fechamento do modal ao clicar fora ou apertar ESC se o usuário não estiver autenticado
    $(document).on('hide.bs.modal', '#shiny-modal', function(e) {
      var isAuth = $('body').hasClass('authenticated');
      var isRec = window.isUserInRecovery() || $('#modal_reset_password_new').length;
      if (!isAuth && isRec && !window.allowRecoveryModalClose) {
        console.warn('[AUTH] Bloqueado fechamento do modal: usuário não autenticado em redefinição obrigatória.');
        e.preventDefault();
        e.stopImmediatePropagation();
        return false;
      }
    });

    // Fechamento do modal (somente permitido para usuário autenticado via botão de alterar senha)
    $(document).on('hidden.bs.modal', '#shiny-modal', function() {
      var btnH = $('#btn_header_change_password');
      if (btnH.length) {
        btnH.prop('disabled', false);
        btnH.find('i').removeClass('fa-spinner fa-spin').addClass('fa-key');
      }
      var isAuth = $('body').hasClass('authenticated');
      if (isAuth) {
        if (window.Shiny && window.Shiny.setInputValue) {
          window.Shiny.setInputValue('reset_modal_closed', Date.now(), {priority: 'event'});
        }
      }
      window.allowRecoveryModalClose = false;
    });

    // Foco automático, atributos anti-autofill, backdrop estático e arrasto (Draggable) do modal
    $(document).on('shown.bs.modal', '#shiny-modal', function() {
      var btnH = $('#btn_header_change_password');
      if (btnH.length) {
        btnH.prop('disabled', false);
        btnH.find('i').removeClass('fa-spinner fa-spin').addClass('fa-key');
      }
      var isAuth = $('body').hasClass('authenticated');
      var isRec = window.isUserInRecovery() || $('#modal_reset_password_new').length;
      if (!isAuth && isRec) {
        var modalData = $('#shiny-modal').data('bs.modal');
        if (modalData) {
          if (modalData._config) {
            modalData._config.backdrop = 'static';
            modalData._config.keyboard = false;
          }
          if (modalData.options) {
            modalData.options.backdrop = 'static';
            modalData.options.keyboard = false;
          }
        }
        $('#shiny-modal').attr('data-backdrop', 'static').attr('data-keyboard', 'false');
      }
      // Reforça atributos anti-autofill para evitar que o Google sobreponha caixas de senhas antigas
      $('#modal_reset_password_new, #modal_reset_password_confirm')
        .attr('autocomplete', 'new-password')
        .attr('data-lpignore', 'true')
        .attr('data-form-type', 'other');

      setTimeout(function() {
        var input = $('#modal_reset_password_new');
        if (input.length) {
          input.focus();
          input.select();
        }
      }, 80);

      // Permite arrastar o modal livremente pelo cabeçalho
      var dialog = $('#shiny-modal .modal-dialog');
      var header = $('#shiny-modal .modal-header');

      header.off('mousedown.drag').on('mousedown.drag', function(e) {
        if ($(e.target).is('button, a, input, i.fa-eye, i.fa-eye-slash, i.fa-xmark')) return;
        var startX = e.clientX;
        var startY = e.clientY;
        var offset = dialog.offset();
        var origX = offset.left;
        var origY = offset.top - $(window).scrollTop();

        dialog.css({
          position: 'fixed',
          margin: '0',
          left: origX + 'px',
          top: origY + 'px',
          right: 'auto',
          bottom: 'auto'
        });

        $(document).on('mousemove.drag', function(ev) {
          var dx = ev.clientX - startX;
          var dy = ev.clientY - startY;
          var newLeft = Math.max(10, Math.min(window.innerWidth - dialog.outerWidth() - 10, origX + dx));
          var newTop = Math.max(10, Math.min(window.innerHeight - 80, origY + dy));
          dialog.css({
            left: newLeft + 'px',
            top: newTop + 'px'
          });
        });

        $(document).on('mouseup.drag', function() {
          $(document).off('mousemove.drag mouseup.drag');
        });
      });
    });
  });

  // 3. Handlers Seguros do Shiny
  function registerShinyHandlers() {
    if (typeof Shiny === 'undefined' || !Shiny.addCustomMessageHandler) {
      setTimeout(registerShinyHandlers, 50);
      return;
    }

    // Handler de estado de autenticação (revelação ou bloqueio do app)
    Shiny.addCustomMessageHandler('set_auth_state', function(isAuth) {
      var elRestoring = document.getElementById('auth_restoring_state');
      var elLogin = document.getElementById('auth_form_login');
      var elSignup = document.getElementById('auth_form_signup');
      var elForgot = document.getElementById('auth_form_forgot');
      var elReset = document.getElementById('auth_form_reset_password');
      var elTabs = document.querySelector('.auth-tabs-nav');

      if (isAuth) {
        sessionRestored = true;
        if (restoreTimeoutFailsafe) {
          clearTimeout(restoreTimeoutFailsafe);
          restoreTimeoutFailsafe = null;
        }
        if (restoreTimer) {
          clearInterval(restoreTimer);
          restoreTimer = null;
        }
        isRecoveryModeActive = false;
        window.currentRecoveryToken = null;
        try {
          sessionStorage.removeItem('quiin_pending_recovery_token');
          sessionStorage.removeItem('quiin_em_redefinicao_senha');
          sessionStorage.removeItem('quiin_recovery_active');
          localStorage.removeItem('quiin_pending_recovery_token');
          localStorage.removeItem('quiin_recovery_active');
        } catch(e) {}
        $('#quiin_recovery_instant_css, #quiin_restore_instant_css, #quiin_early_auth_css, #quiin_instant_auth_css').remove();
        if (window.history && window.history.replaceState) {
          var h = window.location.hash || '';
          var s = window.location.search || '';
          if (h.indexOf('type=recovery') !== -1 || s.indexOf('type=recovery') !== -1) {
            window.history.replaceState(null, document.title, window.location.pathname);
          }
        }

        var btn = $('#btn_login_submit');
        if (btn.length) {
          btn.html('<i class="fa fa-check" style="margin-right: 8px;"></i><span>Acesso autorizado!</span>');
        }
        $('html').addClass('authenticated');
        $('body').addClass('authenticated');
        $('#auth_overlay_root').stop(true, true).fadeOut(250);

        // Prepara o formulário em estado pronto caso o usuário deslogue
        if (elRestoring) elRestoring.style.display = 'none';
        if (elForgot) elForgot.style.display = 'none';
        if (elReset) elReset.style.display = 'none';
        if (elSignup) elSignup.style.display = 'none';
        if (elLogin) elLogin.style.display = 'block';
        if (elTabs) elTabs.style.display = 'flex';
      } else {
        $('html').removeClass('authenticated');
        $('body').removeClass('authenticated');
        $('#quiin_recovery_instant_css, #quiin_restore_instant_css, #quiin_early_auth_css, #quiin_instant_auth_css').remove();

        // Se estiver em modo de recuperação, NUNCA permite exibir o formulário de login
        if (window.isUserInRecovery()) {
          console.warn('[AUTH] Recuperação de senha ativa. Exibição do formulário de login bloqueada.');
          window.enforceResetTab();
          return;
        }

        // Reseta imediatamente o spinner de restauração para o formulário de login limpo
        if (elRestoring) elRestoring.style.display = 'none';
        if (elForgot) elForgot.style.display = 'none';
        if (elReset) elReset.style.display = 'none';
        if (elSignup) elSignup.style.display = 'none';
        if (elLogin) elLogin.style.display = 'block';
        if (elTabs) elTabs.style.display = 'flex';

        // Reseta abas e esconde caixas de erro e mensagens de sucesso
        $('.auth-tab-btn').removeClass('active');
        $('.auth-tab-btn[data-mode="login"]').addClass('active');
        $('#auth_login_error_box, #auth_signup_error_box, #auth_recovery_error_box, #auth_recovery_success_box, #auth_reset_error_box').hide();

        // Limpa campos de credenciais imediatamente ao sair
        var inputsToClear = ['login_email', 'login_password', 'signup_email', 'signup_password', 'signup_password_confirm', 'recovery_email', 'reset_password_new', 'reset_password_confirm'];
        inputsToClear.forEach(function(id) {
          var el = document.getElementById(id);
          if (el) el.value = '';
        });

        var btnLogin = $('#btn_login_submit');
        if (btnLogin.length) {
          btnLogin.prop('disabled', false).removeClass('loading');
          btnLogin.html('<i class="fa fa-right-to-bracket" style="margin-right: 8px;"></i><span>Entrar na Plataforma</span>');
        }
        var btnSignup = $('#btn_signup_submit');
        if (btnSignup.length) {
          btnSignup.prop('disabled', false).removeClass('loading');
          btnSignup.html('<i class="fa fa-user-check" style="margin-right: 8px;"></i><span>Cadastrar e Criar Conta</span>');
        }

        $('#auth_overlay_root').stop(true, true).fadeIn(200);
        sessionRestored = false;
      }
    });

    // Salvar sessão persistente no localStorage e no Supabase SDK
    Shiny.addCustomMessageHandler('save_auth_session', function(data) {
      if (data && (data.access_token || data.refresh_token || data.user)) {
        try {
          localStorage.setItem('quiin_auth_session', JSON.stringify(data));
        } catch(e) {}
        if (supabaseClient && supabaseClient.auth && data.access_token && data.refresh_token) {
          try {
            supabaseClient.auth.setSession({
              access_token: data.access_token,
              refresh_token: data.refresh_token
            });
          } catch(e) {}
        }
      }
    });

    // Limpar sessão persistente no logout
    Shiny.addCustomMessageHandler('clear_auth_session', function(msg) {
      sessionRestored = false;
      if (restoreTimeoutFailsafe) {
        clearTimeout(restoreTimeoutFailsafe);
        restoreTimeoutFailsafe = null;
      }
      if (restoreTimer) {
        clearInterval(restoreTimer);
        restoreTimer = null;
      }
      try {
        localStorage.removeItem('quiin_auth_session');
      } catch(e) {}
      if (supabaseClient && supabaseClient.auth) {
        try { supabaseClient.auth.signOut(); } catch(e) {}
      }
      $('html').removeClass('authenticated');
      $('body').removeClass('authenticated');
      $('#quiin_recovery_instant_css, #quiin_restore_instant_css, #quiin_early_auth_css, #quiin_instant_auth_css').remove();
      $('#auth_overlay_root').stop(true, true).fadeIn(150);

      if (window.isUserInRecovery()) {
        window.enforceResetTab();
        return;
      }

      var elRestoring = document.getElementById('auth_restoring_state');
      var elLogin = document.getElementById('auth_form_login');
      var elSignup = document.getElementById('auth_form_signup');
      var elForgot = document.getElementById('auth_form_forgot');
      var elReset = document.getElementById('auth_form_reset_password');
      var elTabs = document.querySelector('.auth-tabs-nav');
      if (elRestoring) elRestoring.style.display = 'none';
      if (elForgot) elForgot.style.display = 'none';
      if (elReset) elReset.style.display = 'none';
      if (elSignup) elSignup.style.display = 'none';
      if (elLogin) elLogin.style.display = 'block';
      if (elTabs) elTabs.style.display = 'flex';

      var inputsToClear = ['login_email', 'login_password', 'signup_email', 'signup_password', 'signup_password_confirm', 'recovery_email', 'reset_password_new', 'reset_password_confirm'];
      inputsToClear.forEach(function(id) {
        var el = document.getElementById(id);
        if (el) el.value = '';
      });
    });

    // Falha na restauração da sessão silenciosa (revela formulário sem apagar se for falha de rede transitória)
    Shiny.addCustomMessageHandler('restore_auth_failed', function(msg) {
      sessionRestored = false;
      if (restoreTimeoutFailsafe) {
        clearTimeout(restoreTimeoutFailsafe);
        restoreTimeoutFailsafe = null;
      }
      if (restoreTimer) {
        clearInterval(restoreTimer);
        restoreTimer = null;
      }
      if (window.isUserInRecovery()) {
        window.enforceResetTab();
        return;
      }
      $('html').removeClass('authenticated');
      $('body').removeClass('authenticated');
      $('#quiin_recovery_instant_css, #quiin_restore_instant_css, #quiin_early_auth_css, #quiin_instant_auth_css').remove();
      $('#auth_overlay_root').stop(true, true).fadeIn(150);
      var elRestoring = document.getElementById('auth_restoring_state');
      var elLogin = document.getElementById('auth_form_login');
      var elTabs = document.querySelector('.auth-tabs-nav');
      if (elRestoring) elRestoring.style.display = 'none';
      if (elLogin) elLogin.style.display = 'block';
      if (elTabs) elTabs.style.display = 'flex';
    });

    // Falha de login
    Shiny.addCustomMessageHandler('login_failed', function(data) {
      var btn = $('#btn_login_submit');
      btn.prop('disabled', false).removeClass('loading');
      btn.html('<i class="fa fa-right-to-bracket" style="margin-right: 8px;"></i><span>Entrar na Plataforma</span>');

      var msg = (data && data.message) ? data.message : 'Falha na autenticação. Verifique suas credenciais.';
      $('#auth_login_error_text').text(msg);
      $('#auth_login_error_box').stop(true, true).slideDown(150);
    });

    // Falha de cadastro
    Shiny.addCustomMessageHandler('signup_failed', function(data) {
      var btn = $('#btn_signup_submit');
      btn.prop('disabled', false).removeClass('loading');
      btn.html('<i class="fa fa-user-check" style="margin-right: 8px;"></i><span>Cadastrar e Criar Conta</span>');

      var msg = (data && data.message) ? data.message : 'Falha no cadastro.';
      $('#auth_signup_error_text').text(msg);
      $('#auth_signup_error_box').stop(true, true).slideDown(150);
    });

    // Sucesso no envio do link de recuperação
    Shiny.addCustomMessageHandler('recovery_success', function(data) {
      var btn = $('#btn_recovery_submit');
      btn.prop('disabled', false).removeClass('loading');
      btn.html('<i class="fa fa-paper-plane" style="margin-right: 8px;"></i><span>Enviar Link de Recuperação</span>');

      var msg = (data && data.message) ? data.message : 'Link de recuperação enviado com sucesso! Verifique sua caixa de entrada e spam.';
      $('#auth_recovery_error_box').hide();
      $('#auth_recovery_success_text').html(msg + '<br><small style="display:block; margin-top:6px; opacity:0.9;"><strong>Aviso:</strong> Servidores corporativos (@fieb.org.br) podem levar de 1 a 3 minutos para liberar o e-mail na sua caixa.</small>');
      $('#auth_recovery_success_box').stop(true, true).slideDown(150);
    });

    // Falha na recuperação de senha
    Shiny.addCustomMessageHandler('recovery_failed', function(data) {
      var btn = $('#btn_recovery_submit');
      btn.prop('disabled', false).removeClass('loading');
      btn.html('<i class="fa fa-paper-plane" style="margin-right: 8px;"></i><span>Enviar Link de Recuperação</span>');

      var msg = (data && data.message) ? data.message : 'Não foi possível solicitar a recuperação. Verifique o e-mail informado.';
      $('#auth_recovery_success_box').hide();
      $('#auth_recovery_error_text').text(msg);
      $('#auth_recovery_error_box').stop(true, true).slideDown(150);
    });

    // Sucesso na redefinição de senha via link
    Shiny.addCustomMessageHandler('reset_password_success', function(data) {
      window.allowRecoveryModalClose = true;
      isRecoveryModeActive = false;
      window.currentRecoveryToken = null;
      modalTriggerAcknowledged = true;
      if (recoveryPollTimer) {
        clearInterval(recoveryPollTimer);
        recoveryPollTimer = null;
      }
      try {
        sessionStorage.removeItem('quiin_pending_recovery_token');
        sessionStorage.removeItem('quiin_em_redefinicao_senha');
        localStorage.removeItem('quiin_pending_recovery_token');
        sessionStorage.removeItem('quiin_recovery_active');
        localStorage.removeItem('quiin_recovery_active');
      } catch(e) {}
      $('#quiin_recovery_instant_css').remove();
      if (window.history && window.history.replaceState) {
        window.history.replaceState(null, document.title, window.location.pathname);
      }
      $('#shiny-modal').modal('hide');
      var btnM = $('#btn_modal_submit_new_password');
      if (btnM.length) {
        btnM.prop('disabled', false);
        btnM.html('<i class="fa fa-check" style="margin-right: 6px;"></i><span>Salvar Nova Senha</span>');
      }
      var btn = $('#btn_reset_password_submit');
      btn.prop('disabled', false).removeClass('loading');
      btn.html('<i class="fa fa-check" style="margin-right: 8px;"></i><span>Salvar Nova Senha</span>');

      var msg = (data && data.message) ? data.message : 'Senha atualizada com sucesso! Você já pode entrar com sua nova senha.';
      if (!$('body').hasClass('authenticated')) {
        window.exibirModoAuth('login');

        $('#auth_login_error_box').hide();
        $('#auth_login_success_text').text(msg);
        $('#auth_login_success_box').stop(true, true).slideDown(200);

        setTimeout(function() {
          var pwdInp = document.getElementById('login_password');
          var emailInp = document.getElementById('login_email');
          if (emailInp && !emailInp.value.trim()) {
            emailInp.focus();
          } else if (pwdInp) {
            pwdInp.focus();
          }
        }, 250);
      }
    });

    // Cancelamento explícito da recuperação pelo usuário
    Shiny.addCustomMessageHandler('clear_recovery_state', function(data) {
      isRecoveryModeActive = false;
      window.currentRecoveryToken = null;
      modalTriggerAcknowledged = true;
      if (recoveryPollTimer) {
        clearInterval(recoveryPollTimer);
        recoveryPollTimer = null;
      }
      try {
        sessionStorage.removeItem('quiin_pending_recovery_token');
      } catch(e) {}
      $('#quiin_recovery_instant_css').remove();
      if (window.history && window.history.replaceState) {
        window.history.replaceState(null, document.title, window.location.pathname);
      }
      $('#shiny-modal').modal('hide');
      if (!$('body').hasClass('authenticated')) {
        $('.auth-tabs-nav').css('display', 'flex').show();
        $('#auth_form_reset_password').hide();
        $('#auth_form_login').show();
        window.switchAuthTab('login');
      }
    });

    // Confirmação de abertura do modal pelo servidor Shiny
    Shiny.addCustomMessageHandler('reset_modal_opened', function(data) {
      modalTriggerAcknowledged = true;
      if (recoveryPollTimer) {
        clearInterval(recoveryPollTimer);
        recoveryPollTimer = null;
      }
      console.log('[AUTH] Confirmação de abertura do modal de recuperação recebida do servidor Shiny.');
    });

    // Falha na redefinição de senha via link
    Shiny.addCustomMessageHandler('reset_password_failed', function(data) {
      var btnM = $('#btn_modal_submit_new_password');
      if (btnM.length) {
        btnM.prop('disabled', false);
        btnM.html('<i class="fa fa-check" style="margin-right: 6px;"></i><span>Salvar Nova Senha</span>');
      }
      var btn = $('#btn_reset_password_submit');
      btn.prop('disabled', false).removeClass('loading');
      btn.html('<i class="fa fa-check" style="margin-right: 8px;"></i><span>Salvar Nova Senha</span>');

      var msg = (data && data.message) ? data.message : 'Não foi possível redefinir sua senha. O link pode ter expirado.';
      $('#auth_reset_error_text').text(msg);
      $('#auth_reset_error_box').stop(true, true).slideDown(150);
    });

    // Foco e seleção imediata no campo de nova senha após erro de validação/mesma senha
    Shiny.addCustomMessageHandler('modal_reset_error_focus', function() {
      var btnM = $('#btn_modal_submit_new_password');
      if (btnM.length) {
        btnM.prop('disabled', false);
        btnM.html('<i class="fa fa-check" style="margin-right: 6px;"></i><span>Salvar Nova Senha</span>');
      }
      var btn = $('#btn_reset_password_submit');
      if (btn.length) {
        btn.prop('disabled', false).removeClass('loading');
        btn.html('<i class="fa fa-check" style="margin-right: 8px;"></i><span>Atualizar Senha</span>');
      }
      setTimeout(function() {
        var inp = $('#modal_reset_password_new');
        if (inp.length) {
          inp.focus();
          inp.select();
        }
      }, 50);
    });

    // Scroll para logs
    Shiny.addCustomMessageHandler('scroll-logs', function(msg) {
      setTimeout(function() {
        var log_elem = document.getElementById('modal_log_text');
        if (log_elem && log_elem.parentElement) {
          log_elem.parentElement.scrollTop = log_elem.parentElement.scrollHeight;
        }
      }, 50);
    });
  }

  registerShinyHandlers();

  // Função para coletar parâmetros da URL em múltiplos contextos (iframe atual, parent e top)
  function collectAllUrlParams() {
    var params = {};
    var sources = [window.location];

    try {
      if (window.parent && window.parent.location && window.parent !== window) {
        sources.push(window.parent.location);
      }
    } catch(e) {}

    try {
      if (window.top && window.top.location && window.top !== window && window.top !== window.parent) {
        sources.push(window.top.location);
      }
    } catch(e) {}

    sources.forEach(function(loc) {
      try {
        var hash = loc.hash || '';
        var search = loc.search || '';

        [hash, search].forEach(function(str) {
          if (str && str.length > 1) {
            var clean = str.replace(/^[#?]/, '');
            var parts = clean.split('&');
            parts.forEach(function(part) {
              var eqIdx = part.indexOf('=');
              if (eqIdx !== -1) {
                var key = decodeURIComponent(part.substring(0, eqIdx)).trim();
                var val = decodeURIComponent(part.substring(eqIdx + 1)).trim();
                if (key && !params[key]) params[key] = val;
              }
            });
          }
        });
      } catch(err) {}
    });

    return params;
  }

  // Disparo contínuo e confiável da abertura do modal de recuperação no Shiny
  function startRecoveryModalTrigger(token) {
    if (modalTriggerAcknowledged) return;

    if (recoveryPollTimer) {
      clearInterval(recoveryPollTimer);
      recoveryPollTimer = null;
    }

    function sendToShiny() {
      if (modalTriggerAcknowledged || !window.isUserInRecovery()) {
        if (recoveryPollTimer) {
          clearInterval(recoveryPollTimer);
          recoveryPollTimer = null;
        }
        return;
      }
      if (window.Shiny && typeof window.Shiny.setInputValue === 'function') {
        console.log('[AUTH] Enviando trigger_reset_password_modal para o servidor Shiny...');
        window.Shiny.setInputValue('trigger_reset_password_modal', {
          access_token: token,
          timestamp: Date.now()
        }, { priority: 'event' });
      }
    }

    if (window.Shiny && typeof window.Shiny.setInputValue === 'function') {
      sendToShiny();
    }

    $(document).on('shiny:connected shiny:sessioninitialized', function() {
      sendToShiny();
    });

    var pollAttempts = 0;
    recoveryPollTimer = setInterval(function() {
      pollAttempts++;
      if (modalTriggerAcknowledged || pollAttempts > 120 || !window.isUserInRecovery()) {
        clearInterval(recoveryPollTimer);
        recoveryPollTimer = null;
        return;
      }
      sendToShiny();
    }, 250);
  }

  // 4. Detecção e Persistência de Recuperação de Senha na URL (sobrevive a F5 / reload)
  function checkUrlForRecovery() {
    var params = collectAllUrlParams();

    // Uma URL de recuperação genuína deve conter explicitamente type=recovery ou token_hash
    var isRecoveryUrl = (params.type === 'recovery') || 
                        (params.recovery === 'true') || 
                        (window.location.hash.indexOf('type=recovery') !== -1) ||
                        (window.location.search.indexOf('type=recovery') !== -1) ||
                        (window.location.hash.indexOf('token_hash=') !== -1) ||
                        (window.location.search.indexOf('token_hash=') !== -1) ||
                        (params.token_hash && (params.type === 'recovery' || !params.type));

    var storedToken = null;
    try {
      storedToken = sessionStorage.getItem('quiin_pending_recovery_token');
    } catch(e) {}

    var hasSavedAuth = false;
    try {
      hasSavedAuth = !!localStorage.getItem('quiin_auth_session');
    } catch(e) {}

    // Se o usuário já tem sessão salva e a URL NÃO é de recuperação, NUNCA entra em recuperação
    if (hasSavedAuth && !isRecoveryUrl) {
      return false;
    }

    var isRecovery = isRecoveryUrl || (storedToken && storedToken.length > 5);
    var token = params.access_token || params.token || params.code || params.token_hash || storedToken || '';

    if (isRecovery && token) {
      isRecoveryModeActive = true;
      window.currentRecoveryToken = token;

      // Salva no sessionStorage para resistir a F5 / reloads na mesma aba (padrão nei-js)
      try {
        sessionStorage.setItem('quiin_pending_recovery_token', token);
        sessionStorage.setItem('quiin_em_redefinicao_senha', '1');
      } catch(e) {}

      // Limpa qualquer sessão salva de usuário anterior para não reautenticar
      try {
        localStorage.removeItem('quiin_auth_session');
      } catch(e) {}

      // Força a exibição do formulário de redefinição
      window.exibirModoAuth('reset');

      // Dispara registro do token no Shiny
      startRecoveryModalTrigger(token);

      return true;
    }

    if (params.error || params.error_description) {
      isRecoveryErrorActive = true;
      var rawMsg = params.error_description || params.error || '';
      recoveryErrorMessage = rawMsg.replace(/\+/g, ' ');
      window.switchAuthTab('forgot');
      var errBox = $('#auth_recovery_error_box');
      var errText = $('#auth_recovery_error_text');
      errText.text(recoveryErrorMessage || 'O link de recuperação expirou ou é inválido. Por favor, solicite um novo link abaixo.');
      errBox.stop(true, true).slideDown(150);
      return true;
    }

    // Se foi detectada recuperação mas sem token válido (ou token expirado/ausente), limpa e destrava
    if (isRecovery && !token) {
      console.warn('[AUTH] Link de recuperação sem token válido. Destravando para tela de login.');
      window.cancelarRedefinicaoSenha();
      return false;
    }

    return false;
  }

  // 5. Restauração Silenciosa de Sessão Persistente (Padrão Oficial Supabase SDK / nei-js)
  var sessionRestored = false;
  var restoreTimeoutFailsafe = null;
  var restoreTimer = null;

  // Botão de escape / destravamento imediato pelo usuário
  window.cancelRestoreSession = function() {
    console.warn('[AUTH] Restauração cancelada pelo usuário. Destravando formulário de login.');
    sessionRestored = false;
    try {
      localStorage.removeItem('quiin_auth_session');
    } catch(e) {}
    if (supabaseClient && supabaseClient.auth) {
      try { supabaseClient.auth.signOut(); } catch(e) {}
    }
    window.exibirModoAuth('login');
    $('#auth_overlay_root').stop(true, true).fadeIn(150);
  };

  // Envia a sessão para o servidor Shiny
  function enviarSessaoParaShiny(payload) {
    if (sessionRestored) return true;
    try {
      if (window.Shiny && typeof window.Shiny.setInputValue === 'function') {
        sessionRestored = true;
        console.log('[AUTH] Enviando restore_auth_session para o servidor Shiny...');
        window.Shiny.setInputValue('restore_auth_session', payload, {priority: 'event'});
        return true;
      }
    } catch(e) {
      console.warn('[AUTH] Erro ao enviar restore_auth_session:', e);
    }
    return false;
  }

  // Listener oficial do Supabase SDK (idêntico ao padrão nei-js)
  if (supabaseClient && supabaseClient.auth && typeof supabaseClient.auth.onAuthStateChange === 'function') {
    supabaseClient.auth.onAuthStateChange(function(evento, session) {
      console.log('[AUTH] onAuthStateChange:', evento, session ? session.user.email : 'sem sessao');
      if (evento === 'PASSWORD_RECOVERY') {
        sessionStorage.setItem('quiin_em_redefinicao_senha', '1');
        sessionStorage.setItem('nei_em_redefinicao_senha', '1');
        isRecoveryModeActive = true;
        window.exibirModoAuth('reset');
      } else if (evento === 'SIGNED_IN' || evento === 'TOKEN_REFRESHED') {
        if (session && session.user && !isRecoveryModeActive) {
          var payload = {
            access_token: session.access_token,
            refresh_token: session.refresh_token,
            user: {
              id: session.user.id,
              email: session.user.email,
              role: session.user.role || 'authenticated'
            }
          };
          try { localStorage.setItem('quiin_auth_session', JSON.stringify(payload)); } catch(e) {}
          $('html').addClass('authenticated');
          $('body').addClass('authenticated');
          $('#auth_overlay_root').hide();
          enviarSessaoParaShiny(payload);
        }
      } else if (evento === 'SIGNED_OUT') {
        if (!isRecoveryModeActive) {
          try { localStorage.removeItem('quiin_auth_session'); } catch(e) {}
          $('html').removeClass('authenticated');
          $('body').removeClass('authenticated');
          $('#auth_overlay_root').show();
          window.exibirModoAuth('login');
        }
      }
    });
  }

  function initSessionRestore() {
    if (sessionRestored) return;

    // Se estiver em modo de recuperação, executa verificação de recuperação
    if (window.isUserInRecovery && window.isUserInRecovery()) {
      if (checkUrlForRecovery()) return;
      window.exibirModoAuth('reset');
      return;
    }

    // Purga quaisquer chaves legadas de recuperação se não estiver em recuperação válida
    try {
      if (!window.isUserInRecovery || !window.isUserInRecovery()) {
        localStorage.removeItem('quiin_pending_recovery_token');
        localStorage.removeItem('quiin_recovery_active');
        sessionStorage.removeItem('quiin_pending_recovery_token');
        sessionStorage.removeItem('quiin_em_redefinicao_senha');
        sessionStorage.removeItem('nei_em_redefinicao_senha');
        sessionStorage.removeItem('quiin_recovery_active');
      }
    } catch(e) {}

    var params = collectAllUrlParams();
    var isRecoveryUrl = (params.type === 'recovery') || 
                        (params.recovery === 'true') || 
                        (window.location.hash.indexOf('type=recovery') !== -1) || 
                        (window.location.search.indexOf('type=recovery') !== -1) ||
                        (window.location.hash.indexOf('token_hash=') !== -1) ||
                        (window.location.search.indexOf('token_hash=') !== -1);

    // Se a URL contém explicitamente link de recuperação de senha por email, prioriza recuperação
    if (isRecoveryUrl) {
      if (checkUrlForRecovery()) return;
    }

    // 1. Tenta restaurar sessão via SDK Oficial do Supabase (getSession - padrão nei-js)
    if (supabaseClient && supabaseClient.auth && typeof supabaseClient.auth.getSession === 'function') {
      supabaseClient.auth.getSession().then(function(res) {
        if (res && res.data && res.data.session && res.data.session.user) {
          var s = res.data.session;
          var sdkPayload = {
            access_token: s.access_token,
            refresh_token: s.refresh_token,
            user: {
              id: s.user.id,
              email: s.user.email,
              role: s.user.role || 'authenticated'
            }
          };
          try { localStorage.setItem('quiin_auth_session', JSON.stringify(sdkPayload)); } catch(e) {}
          $('html').addClass('authenticated');
          $('body').addClass('authenticated');
          $('#auth_overlay_root').hide();

          if (!enviarSessaoParaShiny(sdkPayload)) {
            $(document).off('shiny:connected.sdk').on('shiny:connected.sdk', function() {
              enviarSessaoParaShiny(sdkPayload);
            });
          }
          return;
        }
      }).catch(function(err) {
        console.warn('[AUTH] Aviso getSession:', err);
      });
    }

    // 2. Leitura síncrona imediata do localStorage para não ter flash de tela no F5
    var saved = null;
    try {
      saved = localStorage.getItem('quiin_auth_session');
    } catch(e) {}

    var sessionData = null;
    if (saved) {
      try {
        sessionData = JSON.parse(saved);
      } catch(e) {}
    }
    var hasValidSavedSession = !!(sessionData && (sessionData.access_token || sessionData.refresh_token || sessionData.user));

    if (hasValidSavedSession && !isRecoveryUrl) {
      try {
        sessionStorage.removeItem('quiin_pending_recovery_token');
        sessionStorage.removeItem('quiin_em_redefinicao_senha');
        sessionStorage.removeItem('nei_em_redefinicao_senha');
        sessionStorage.removeItem('quiin_recovery_active');
      } catch(e) {}
    }

    if (!hasValidSavedSession) {
      if (window.isUserInRecovery && window.isUserInRecovery()) {
        if (checkUrlForRecovery()) return;
        window.exibirModoAuth('reset');
        return;
      }
      // Se não há sessão salva, exibe formulário de login normalmente
      window.exibirModoAuth('login');
      return;
    }

    // Se o usuário tem sessão salva legítima e não está em link de recuperação:
    // Destrava imediatamente o layout e oculta o overlay
    $('html').addClass('authenticated');
    $('body').addClass('authenticated');
    $('#auth_overlay_root').hide();

    if (!enviarSessaoParaShiny(sessionData)) {
      $(document).off('shiny:connected.restore').on('shiny:connected.restore', function() {
        enviarSessaoParaShiny(sessionData);
      });
      var attempts = 0;
      var restoreTimer = setInterval(function() {
        attempts++;
        if (sessionRestored || attempts >= 100) {
          clearInterval(restoreTimer);
          return;
        }
        if (enviarSessaoParaShiny(sessionData)) {
          clearInterval(restoreTimer);
        }
      }, 100);
    }
  }

  // Inicia detecção de recuperação e restauração de forma unificada e segura
  function handleInitialAuthState() {
    initSessionRestore();
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', handleInitialAuthState);
  } else {
    handleInitialAuthState();
  }
  if (window.$) {
    $(document).ready(handleInitialAuthState);
    $(document).on('shiny:connected', handleInitialAuthState);
  } else {
    document.addEventListener('DOMContentLoaded', function() {
      if (window.$) {
        $(document).ready(handleInitialAuthState);
        $(document).on('shiny:connected', handleInitialAuthState);
      }
    });
  }

})();

