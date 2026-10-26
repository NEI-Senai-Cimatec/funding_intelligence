// ============================================================================
// Funding Intelligence - Autenticação Supabase, Sessão e Interface de Acesso
// SENAI CIMATEC – Núcleo de Economia Industrial (NEI)
// ============================================================================

(function() {
  'use strict';

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
    var redirectUri = window.location.origin + window.location.pathname;
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
      errText.text('Por favor, preencha e confirme sua nova senha.');
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

    btn.prop('disabled', true).addClass('loading');
    btn.html('<i class="fa fa-spinner fa-spin" style="margin-right: 8px;"></i><span>Atualizando senha...</span>');

    var token = window.currentRecoveryToken || '';
    var payload = { password: pwd, access_token: token, timestamp: Date.now() };

    if (window.Shiny && window.Shiny.setInputValue) {
      Shiny.setInputValue('btn_reset_password_submit', payload, {priority: 'event'});
    } else {
      setTimeout(function() {
        if (window.Shiny && window.Shiny.setInputValue) {
          Shiny.setInputValue('btn_reset_password_submit', payload, {priority: 'event'});
        } else {
          btn.prop('disabled', false).removeClass('loading');
          btn.html('<i class="fa fa-check" style="margin-right: 8px;"></i><span>Atualizar Senha</span>');
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

  // 2. Função de Alternância de Abas Instantânea (Login, Cadastro, Recuperar e Redefinir)
  window.switchAuthTab = function(mode) {
    var tabsNav = $('.auth-tabs-nav');
    $('.auth-tab-btn').removeClass('active');

    var formLogin = document.getElementById('auth_form_login');
    var formSignup = document.getElementById('auth_form_signup');
    var formForgot = document.getElementById('auth_form_forgot');
    var formReset = document.getElementById('auth_form_reset_password');

    // Se os elementos ainda não foram carregados no DOM, agenda para quando o DOM estiver pronto
    if (!formLogin && !formReset) {
      $(document).ready(function() {
        window.switchAuthTab(mode);
      });
      return;
    }

    // Limpa caixas de erro e mensagens de sucesso
    $('#auth_login_error_box, #auth_signup_error_box, #auth_recovery_error_box, #auth_recovery_success_box, #auth_reset_error_box').hide();

    // Reseta botões se estiverem em loading
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
    btnReset.html('<i class="fa fa-check" style="margin-right: 8px;"></i><span>Atualizar Senha</span>');

    if (mode === 'reset' || isRecoveryModeActive) {
      tabsNav.hide();
      $('body').removeClass('authenticated');
      $('#auth_overlay_root').show();
      var elRestoring = document.getElementById('auth_restoring_state');
      if (elRestoring) elRestoring.style.display = 'none';
      if (formLogin) formLogin.style.display = 'none';
      if (formSignup) formSignup.style.display = 'none';
      if (formForgot) formForgot.style.display = 'none';
      if (formReset) {
        formReset.style.display = 'block';
        var resetPwd = document.getElementById('reset_password_new');
        if (resetPwd) resetPwd.focus();
      }
    } else if (mode === 'forgot') {
      tabsNav.hide();
      if (formLogin) formLogin.style.display = 'none';
      if (formSignup) formSignup.style.display = 'none';
      if (formReset) formReset.style.display = 'none';
      if (formForgot) {
        formForgot.style.display = 'block';
        var loginEmail = document.getElementById('login_email');
        var recoveryEmail = document.getElementById('recovery_email');
        if (loginEmail && recoveryEmail && loginEmail.value.trim() && !recoveryEmail.value.trim()) {
          recoveryEmail.value = loginEmail.value.trim();
        }
        if (recoveryEmail) recoveryEmail.focus();
      }
    } else if (mode === 'signup') {
      tabsNav.show();
      $('.auth-tab-btn[data-mode="signup"]').addClass('active');
      if (formLogin) formLogin.style.display = 'none';
      if (formForgot) formForgot.style.display = 'none';
      if (formReset) formReset.style.display = 'none';
      if (formSignup) formSignup.style.display = 'block';
    } else { // default: login
      tabsNav.show();
      $('.auth-tab-btn[data-mode="login"]').addClass('active');
      if (formSignup) formSignup.style.display = 'none';
      if (formForgot) formForgot.style.display = 'none';
      if (formReset) formReset.style.display = 'none';
      if (formLogin) formLogin.style.display = 'block';
    }
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

    // Submissão com tecla ENTER nos campos
    $(document).on('keypress', '#login_email, #login_password', function(e) {
      if (e.which === 13) {
        e.preventDefault();
        window.submitLoginForm();
      }
    });

    $(document).on('keypress', '#signup_email, #signup_password, #signup_password_confirm', function(e) {
      if (e.which === 13) {
        e.preventDefault();
        window.submitSignupForm();
      }
    });

    $(document).on('keypress', '#recovery_email', function(e) {
      if (e.which === 13) {
        e.preventDefault();
        window.submitRecoveryForm();
      }
    });

    $(document).on('keypress', '#reset_password_new, #reset_password_confirm', function(e) {
      if (e.which === 13) {
        e.preventDefault();
        window.submitResetPasswordForm();
      }
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
        if (isRecoveryModeActive || window.currentRecoveryToken) {
          console.warn('[AUTH] Ignorando autenticação automática porque está no modo de recuperação de senha.');
          window.switchAuthTab('reset');
          return;
        }
        var btn = $('#btn_login_submit');
        if (btn.length) {
          btn.html('<i class="fa fa-check" style="margin-right: 8px;"></i><span>Acesso autorizado!</span>');
        }
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
        $('body').removeClass('authenticated');

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

    // Salvar sessão persistente no localStorage
    Shiny.addCustomMessageHandler('save_auth_session', function(data) {
      if (data && (data.access_token || data.refresh_token || data.user)) {
        try {
          localStorage.setItem('quiin_auth_session', JSON.stringify(data));
        } catch(e) {}
      }
    });

    // Limpar sessão persistente no logout
    Shiny.addCustomMessageHandler('clear_auth_session', function(msg) {
      try {
        localStorage.removeItem('quiin_auth_session');
      } catch(e) {}
      sessionRestored = false;

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
      $('#auth_recovery_success_text').text(msg);
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
      isRecoveryModeActive = false;
      window.currentRecoveryToken = null;
      var btn = $('#btn_reset_password_submit');
      btn.prop('disabled', false).removeClass('loading');
      btn.html('<i class="fa fa-check" style="margin-right: 8px;"></i><span>Atualizar Senha</span>');

      var msg = (data && data.message) ? data.message : 'Senha atualizada com sucesso! Você já pode entrar com sua nova senha.';
      window.switchAuthTab('login');
      $('#auth_login_success_text').text(msg);
      $('#auth_login_success_box').stop(true, true).slideDown(200);
    });

    // Falha na redefinição de senha via link
    Shiny.addCustomMessageHandler('reset_password_failed', function(data) {
      var btn = $('#btn_reset_password_submit');
      btn.prop('disabled', false).removeClass('loading');
      btn.html('<i class="fa fa-check" style="margin-right: 8px;"></i><span>Atualizar Senha</span>');

      var msg = (data && data.message) ? data.message : 'Não foi possível redefinir sua senha. O link pode ter expirado.';
      $('#auth_reset_error_text').text(msg);
      $('#auth_reset_error_box').stop(true, true).slideDown(150);
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

  // 4. Detecção de Link de Recuperação de Senha na URL
  function checkUrlForRecovery() {
    if (isRecoveryModeActive) {
      window.switchAuthTab('reset');
      return true;
    }
    if (isRecoveryErrorActive) {
      window.switchAuthTab('forgot');
      var errBox = $('#auth_recovery_error_box');
      var errText = $('#auth_recovery_error_text');
      errText.text(recoveryErrorMessage || 'O link de recuperação expirou ou é inválido. Por favor, solicite um novo link abaixo.');
      errBox.stop(true, true).slideDown(150);
      return true;
    }

    var hash = window.location.hash || '';
    var search = window.location.search || '';
    var params = {};

    if (hash && hash.length > 1) {
      var hashParts = hash.substring(1).split('&');
      hashParts.forEach(function(part) {
        var kv = part.split('=');
        if (kv.length === 2) {
          params[decodeURIComponent(kv[0])] = decodeURIComponent(kv[1]);
        }
      });
    }

    if (search && search.length > 1) {
      var searchParts = search.substring(1).split('&');
      searchParts.forEach(function(part) {
        var kv = part.split('=');
        if (kv.length === 2) {
          params[decodeURIComponent(kv[0])] = decodeURIComponent(kv[1]);
        }
      });
    }

    if (params.type === 'recovery' && params.access_token) {
      isRecoveryModeActive = true;
      window.currentRecoveryToken = params.access_token;

      // Limpa qualquer sessão salva para não reautenticar por cima da redefinição
      try {
        localStorage.removeItem('quiin_auth_session');
      } catch(e) {}
      $('body').removeClass('authenticated');
      $('#auth_overlay_root').show();

      if (window.history && window.history.replaceState) {
        window.history.replaceState(null, document.title, window.location.pathname + window.location.search);
      }
      window.switchAuthTab('reset');
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
    return false;
  }

  // 5. Restauração Silenciosa com Polling Robusto (SEM piscar formulário)
  var sessionRestored = false;
  function initSessionRestore() {
    if (sessionRestored) return;

    // Se estiver em modo de recuperação de senha, JAMAIS restaura sessão antiga
    if (isRecoveryModeActive || window.currentRecoveryToken) {
      console.log('[AUTH] Recuperação de senha ativa. Restauração de sessão persistente ignorada.');
      return;
    }

    // Se a URL contém token de recuperação de senha, prioriza o fluxo de recuperação
    if (checkUrlForRecovery()) return;

    var saved = null;
    try {
      saved = localStorage.getItem('quiin_auth_session');
    } catch(e) {}
    if (!saved) return;

    var sessionData = null;
    try {
      sessionData = JSON.parse(saved);
    } catch(e) {}
    if (!sessionData || (!sessionData.access_token && !sessionData.refresh_token && !sessionData.user)) return;

    // Se temos uma sessão salva, esconde imediatamente o formulário de login e mostra o restoring spinner
    var elLogin = document.getElementById('auth_form_login');
    var elSignup = document.getElementById('auth_form_signup');
    var elForgot = document.getElementById('auth_form_forgot');
    var elReset = document.getElementById('auth_form_reset_password');
    var elTabs = document.querySelector('.auth-tabs-nav');
    var elRestoring = document.getElementById('auth_restoring_state');
    if (elLogin) elLogin.style.display = 'none';
    if (elSignup) elSignup.style.display = 'none';
    if (elForgot) elForgot.style.display = 'none';
    if (elReset) elReset.style.display = 'none';
    if (elTabs) elTabs.style.display = 'none';
    if (elRestoring) elRestoring.style.display = 'block';

    var attempts = 0;
    var maxAttempts = 120; // 12 segundos
    var restoreTimer = setInterval(function() {
      attempts++;
      if (sessionRestored) {
        clearInterval(restoreTimer);
        return;
      }
      if (isRecoveryModeActive || window.currentRecoveryToken) {
        clearInterval(restoreTimer);
        window.switchAuthTab('reset');
        return;
      }
      if (window.Shiny && window.Shiny.setInputValue && window.Shiny.shinyapp && window.Shiny.shinyapp.isConnected()) {
        sessionRestored = true;
        clearInterval(restoreTimer);
        console.log('[AUTH] Enviando restore_auth_session para o servidor Shiny...');
        window.Shiny.setInputValue('restore_auth_session', sessionData, {priority: 'event'});
      } else if (attempts >= maxAttempts) {
        clearInterval(restoreTimer);
        console.warn('[AUTH] Timeout aguardando conexao Shiny para restaurar sessao.');
        if (elRestoring) elRestoring.style.display = 'none';
        if (elLogin) elLogin.style.display = 'block';
        if (elTabs) elTabs.style.display = 'flex';
      }
    }, 100);
  }

  // Inicia detecção de recuperação e restauração imediatamente e quando o DOM estiver pronto
  checkUrlForRecovery();
  initSessionRestore();
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', function() {
      checkUrlForRecovery();
      initSessionRestore();
    });
  }
  $(document).ready(function() {
    checkUrlForRecovery();
    initSessionRestore();
  });
  $(document).on('shiny:connected', function() {
    checkUrlForRecovery();
    initSessionRestore();
  });

})();
