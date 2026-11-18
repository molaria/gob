<?php

namespace Drupal\gob_attendance\EventSubscriber;

use Drupal\Core\Messenger\MessengerInterface;
use Drupal\Core\Session\AccountInterface;
use Drupal\Core\Url;
use Symfony\Component\EventDispatcher\EventSubscriberInterface;
use Symfony\Component\HttpFoundation\RedirectResponse;
use Symfony\Component\HttpKernel\Event\ExceptionEvent;
use Symfony\Component\HttpKernel\Exception\AccessDeniedHttpException;
use Symfony\Component\HttpKernel\KernelEvents;

/**
 * Turns a denied answer click into a friendly redirect.
 *
 * The answer links carry a session-bound CSRF token. A page that was loaded
 * before a logout/login, or after the session expired, holds links that are
 * now invalid, and members would otherwise meet a bare "Access denied" page.
 */
class AnswerAccessDeniedSubscriber implements EventSubscriberInterface {

  /**
   * Routes whose denied requests get the friendly handling.
   */
  protected const ROUTES = ['gob_attendance.set', 'gob_fika.set'];

  public function __construct(
    protected AccountInterface $currentUser,
    protected MessengerInterface $messenger,
  ) {}

  public static function getSubscribedEvents(): array {
    // Run before core's default 403 handlers so we can replace the response.
    return [KernelEvents::EXCEPTION => ['onException', 50]];
  }

  public function onException(ExceptionEvent $event): void {
    if (!$event->getThrowable() instanceof AccessDeniedHttpException) {
      return;
    }
    if (!in_array($event->getRequest()->attributes->get('_route'), self::ROUTES, TRUE)) {
      return;
    }

    if ($this->currentUser->isAuthenticated()) {
      // Most likely a stale page; a fresh calendar has valid links again.
      $this->messenger->addWarning('Sidan hade hunnit bli gammal, så ditt svar sparades inte. Tryck på knappen igen.');
      $url = Url::fromRoute('view.kalendarium.page_1')->toString();
    }
    else {
      $this->messenger->addWarning('Du har blivit utloggad. Logga in igen, så kommer du tillbaka till kalendariet och kan svara.');
      $url = Url::fromRoute('user.login', [], ['query' => ['destination' => '/kalendarium']])->toString();
    }
    // Core's redirect subscriber swaps the target for ?destination= when it is
    // present, which would send a logged-out member to the (denied) calendar
    // instead of the login page. Drop it so our own target is used.
    $event->getRequest()->query->remove('destination');
    $event->setResponse(new RedirectResponse($url));
  }

}
