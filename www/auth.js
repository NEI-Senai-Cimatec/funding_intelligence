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

    // Limpa quaisquer tokens residuais de recuperação anteriores para não interferir no login
    try {
      sessionStorage.removeItem('quiin_pending_recovery_token');
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
    if ($('body').hasClass('authenticated') || $('html').hasClass('authenticated')) return false;

    var params = collectAllUrlParams();
    var hasRecoveryUrl = (params.type === 'recovery') || 
                         (params.recovery === 'true') || 
                         (window.location.hash.indexOf('type=recovery') !== -1) ||
                         (window.location.search.indexOf('type=recovery') !== -1);

    var hasSavedAuth = false;
    try {
      hasSavedAuth = !!localStorage.getItem('quiin_auth_session');
    } catch(e) {}

    // Se o usuário já possui sessão salva e a URL NÃO é explicitamente de recuperação, NUNCA está em recuperação
    if (hasSavedAuth && !hasRecoveryUrl) return false;

    var stored = null;
    try {
      stored = sessionStorage.getItem('quiin_pending_recovery_token');
    } catch(e) {}
    return isRecoveryModeActive || hasRecoveryUrl || (!!stored && stored.length > 5);
  };

  // Força a exibição imediata e incontestável do formulário de criação de nova senha
  window.enforceResetTab = function() {
    var tabsNav = $('.auth-tabs-nav');
    tabsNav.hide();
    $('body').removeClass('authenticated');
    $('#auth_overlay_root').show();

    var elRestoring = document.getElementById('auth_restoring_state');
    var elLogin = document.getElementById('auth_form_login');
    var elSignup = document.getElementById('auth_form_signup');
    var elForgot = document.getElementById('auth_form_forgot');
    var elReset = document.getElementById('auth_form_reset_password');

    if (elRestoring) elRestoring.style.display = 'none';
    if (elLogin) elLogin.style.display = 'none';
    if (elSignup) elSignup.style.display = 'none';
    if (elForgot) elForgot.style.display = 'none';
    if (elReset) {
      elReset.style.display = 'block';
      var resetPwd = document.getElementById('reset_password_new');
      if (resetPwd) {
        setTimeout(function() { resetPwd.focus(); }, 60);
      }
    }
  };

  // 2. Função de Alternância de Abas Instantânea (Login, Cadastro, Recuperar e Redefinir)
  window.switchAuthTab = function(mode) {
    if (mode === 'login' && window.isUserInRecovery()) {
      isRecoveryModeActive = false;
      window.currentRecoveryToken = null;
      try { sessionStorage.removeItem('quiin_pending_recovery_token'); } catch(e) {}
      $('#quiin_recovery_instant_css').remove();
    } else if (window.isUserInRecovery() && mode !== 'reset') {
      console.warn('[AUTH] Bloqueando alternância de aba durante recuperação de senha pendente.');
      window.enforceResetTab();
      return;
    }

    var tabsNav = $('.auth-tabs-nav');
    $('.auth-tab-btn').removeClass('active');

    var formLogin = document.getElementById('auth_form_login');
    var formSignup = document.getElementById('auth_form_signup');
    var formForgot = document.getElementById('auth_form_forgot');
    var formReset = document.getElementById('auth_form_reset_password');

    // Se os elementos ainda não foram carregados no DOM, agenda para quando o DOM estiver pronto
    if (!formLogin || !formReset) {
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

    if (mode === 'reset' || window.isUserInRecovery()) {
      window.enforceResetTab();
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
        isRecoveryModeActive = false;
        window.currentRecoveryToken = null;
        try {
          sessionStorage.removeItem('quiin_pending_recovery_token');
          sessionStorage.removeItem('quiin_recovery_active');
          localStorage.removeItem('quiin_pending_recovery_token');
          localStorage.removeItem('quiin_recovery_active');
        } catch(e) {}
        $('#quiin_recovery_instant_css').remove();
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
        $('#auth_overlay_root').stop(true, true).hide();

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
        $('#quiin_early_auth_css, #quiin_instant_auth_css').remove();

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
      $('html').removeClass('authenticated');
      $('body').removeClass('authenticated');
      $('#quiin_early_auth_css, #quiin_instant_auth_css').remove();
      $('#auth_overlay_root').css('display', 'flex').show();

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
      if (window.isUserInRecovery()) {
        window.enforceResetTab();
        return;
      }
      $('html').removeClass('authenticated');
      $('body').removeClass('authenticated');
      $('#quiin_early_auth_css, #quiin_instant_auth_css').remove();
      $('#auth_overlay_root').css('display', 'flex').show();
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
      btn.html('<i class="fa fa-check" style="margin-right: 8px;"></i><span>Atualizar Senha</span>');

      var msg = (data && data.message) ? data.message : 'Senha atualizada com sucesso! Você já pode entrar com sua nova senha.';
      if (!$('body').hasClass('authenticated')) {
        // Direciona direta e necessariamente para o modal/card de login
        $('#auth_overlay_root').css('display', 'flex').show();
        $('#auth_restoring_state').hide();
        $('#auth_form_signup, #auth_form_forgot, #auth_form_reset_password').hide();
        $('#auth_form_login').show();
        $('.auth-tabs-nav').css('display', 'flex').show();
        $('.auth-tab-btn').removeClass('active');
        $('.auth-tab-btn[data-mode="login"]').addClass('active');

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
      btn.html('<i class="fa fa-check" style="margin-right: 8px;"></i><span>Atualizar Senha</span>');

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
      if (window.Shiny && window.Shiny.setInputValue && window.Shiny.shinyapp && window.Shiny.shinyapp.isConnected()) {
        console.log('[AUTH] Enviando trigger_reset_password_modal para o servidor Shiny...');
        window.Shiny.setInputValue('trigger_reset_password_modal', {
          access_token: token,
          timestamp: Date.now()
        }, { priority: 'event' });
      }
    }

    if (window.Shiny && window.Shiny.shinyapp && window.Shiny.shinyapp.isConnected()) {
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

    // Uma URL de recuperação genuína deve conter explicitamente type=recovery (padrão Supabase Auth)
    var isRecoveryUrl = (params.type === 'recovery') || 
                        (params.recovery === 'true') || 
                        (window.location.hash.indexOf('type=recovery') !== -1) ||
                        (window.location.search.indexOf('type=recovery') !== -1) ||
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

      // Salva apenas no sessionStorage da aba atual (NUNCA no localStorage global)
      try {
        sessionStorage.setItem('quiin_pending_recovery_token', token);
      } catch(e) {}

      // Só limpa a sessão salva se a URL atual for explicitamente um novo link de recuperação por email
      if (isRecoveryUrl) {
        try {
          localStorage.removeItem('quiin_auth_session');
        } catch(e) {}
      }

      // Força a exibição do formulário de redefinição
      window.enforceResetTab();

      // Dispara abertura do modal dedicado no Shiny de forma persistente
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
    return false;
  }

  // 5. Restauração Silenciosa com Polling Robusto (SEM piscar formulário)
  var sessionRestored = false;
  function initSessionRestore() {
    if (sessionRestored) return;

    // Purga quaisquer chaves legadas de recuperação em localStorage
    try {
      localStorage.removeItem('quiin_pending_recovery_token');
      localStorage.removeItem('quiin_recovery_active');
    } catch(e) {}

    var params = collectAllUrlParams();
    var isRecoveryUrl = (params.type === 'recovery') || 
                        (params.recovery === 'true') || 
                        (window.location.hash.indexOf('type=recovery') !== -1) || 
                        (window.location.search.indexOf('type=recovery') !== -1);

    // Se a URL contém explicitamente link de recuperação de senha por email, prioriza recuperação
    if (isRecoveryUrl) {
      if (checkUrlForRecovery()) return;
    }

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

    if (!hasValidSavedSession) {
      // Usuário não tem sessão salva: verifica se há recuperação pendente nesta aba
      if (checkUrlForRecovery()) return;
      return;
    }

    // Se chegamos aqui, o usuário tem sessão salva legítima e não está acessando um link de recuperação
    // Oculta imediatamente o overlay e ativa a classe authenticated para manter o app destravado
    $('html').addClass('authenticated');
    $('body').addClass('authenticated');
    $('#auth_overlay_root').hide();

    function doSendRestore() {
      if (sessionRestored) return true;
      if (window.Shiny && window.Shiny.setInputValue) {
        sessionRestored = true;
        console.log('[AUTH] Enviando restore_auth_session para o servidor Shiny...');
        window.Shiny.setInputValue('restore_auth_session', sessionData, {priority: 'event'});
        return true;
      }
      return false;
    }

    if (!doSendRestore()) {
      $(document).on('shiny:connected', function() {
        doSendRestore();
      });
      var attempts = 0;
      var restoreTimer = setInterval(function() {
        attempts++;
        if (sessionRestored) {
          clearInterval(restoreTimer);
          return;
        }
        if (doSendRestore() || attempts >= 100) {
          clearInterval(restoreTimer);
        }
      }, 100);
    }
  }

  // Inicia detecção de recuperação e restauração de forma unificada e segura
  function handleInitialAuthState() {
    initSessionRestore();
  }

  handleInitialAuthState();
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', handleInitialAuthState);
  }
  $(document).ready(handleInitialAuthState);
  $(document).on('shiny:connected', handleInitialAuthState);

})();
