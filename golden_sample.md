# GOLDEN SAMPLE (Narrative Technical Style)

## The ViewModel Pattern

In the Chassis architecture, the ViewModel serves as the bridge between your business logic and your user interface. Its primary responsibility is to transform complex domain data into a state that is ready for the UI to render, while simultaneously handling user interactions.

Unlike traditional controllers that might manipulate widgets directly, a Chassis ViewModel relies exclusively on state mutation. When a user interacts with the application—for example, by tapping a "Refresh" button—the ViewModel does not modify the view directly. Instead, it dispatches a command to the Mediator and updates its internal state based on the result.

### Managing State vs. Events

A common architectural challenge is distinguishing between persistent state and ephemeral events.

**State** represents the data that should be displayed on the screen at any given moment, such as a list of users or the text in a form field. If the user rotates their device or navigates away and back, this state should persist.

**Events**, in contrast, are one-time occurrences. A snackbar notification, a navigation action, or a vibration feedback are ephemeral; they happen once and should not be replayed if the UI rebuilds. Chassis solves this by providing distinct channels for `state` (observed by the UI) and `events` (listened to by the `ConsumerMixin`).